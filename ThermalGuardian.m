function ThermalGuardian()
% =========================================================================
%  PCB THERMAL GUARDIAN  (version 2)
%  An embedded + IoT "digital twin" that PREDICTS and PREVENTS electrical
%  fires in everyday power strips / chargers.
%
%  HOW TO RUN (MATLAB R2017b, no toolboxes needed):
%     1) Save this file as  ThermalGuardian.m
%     2) Press the green RUN button   (or type  ThermalGuardian  and Enter)
%     3) Wait about 1 minute. THREE figure windows will open.
%
%  THE DAILY-LIFE PROBLEM
%     A power strip sits under a blanket (cannot cool) and its plug slowly
%     becomes loose. A loose contact has high resistance -> heat = I^2 * R.
%     Nobody notices until it is too late. This is a real cause of home fires.
%
%  WHAT THIS PROJECT CONTAINS
%     1. 2-D PCB heat-flow physics (finite difference, temperature-dependent
%        copper resistance -> positive feedback / thermal runaway)
%     2. Real sensor chain: NTC thermistor + 10-bit ADC + noise + EMI glitches
%     3. Kalman filter (golden reference, floating point)
%     4. SAME filter in integer-only fixed-point (Q8/Q15) = what a cheap MCU
%        without FPU runs.  Float-vs-fixed error is measured.
%     5. Outlier gating + re-lock (robust to glitches)
%     6. CUSUM abnormal-heating detector + "time-to-danger" countdown
%     7. Safety state machine with hysteresis (no chattering):
%        SAFE > WATCH > SLOW DOWN > POWER OFF
%     8. Closed-loop test: WITHOUT vs WITH the Guardian + healthy-board test
%     9. MONTE-CARLO test: 30 random faulty houses + 10 healthy houses
%    10. IoT: event-driven reporting (fewer packets, same information)
%    11. IPC-2221 trace-width design check
%    12. Auto-generates firmware header  guardian_constants.h  (C code)
%
%  All parameters are representative values for a simulation. For a real
%  product they are calibrated with a thermal camera.
% =========================================================================
close all; clc;

P  = defineParameters();
Fl = designFilter(P);

rng(7, 'twister');                                   % same result every run
N = makeNoise(P);

deg   = char(176);
line1 = repmat('=', 1, 72);
fprintf('\n%s\n', line1);
fprintf('   PCB THERMAL GUARDIAN  -  stopping home electrical fires before they start\n');
fprintf('%s\n\n', line1);
fprintf('Simulating (about 1 minute, please wait)...\n');

T0   = warmUp(P, 3000);
gain = calibrateGain(P, T0);

A = runScenario(P, Fl, N, T0, gain, false, false);   % fault, NO guardian
B = runScenario(P, Fl, N, T0, gain, true,  false);   % fault, WITH guardian
H = runScenario(P, Fl, N, T0, gain, true,  true);    % healthy board test

fprintf('Main test done. Now testing 40 random houses...\n');
MC = monteCarlo(P, Fl, gain, 30, 10);

% ---------------------------------------------------------------- report
fprintf('\n%s\n', line1);
fprintf('   EXPLAINED SIMPLY (like for a 5th-class student)\n');
fprintf('%s\n', line1);
fprintf(' * A plug is like a water pipe joint. If it gets loose, it gets HOT.\n');
fprintf(' * A blanket on top is like wearing a jacket in summer: heat cannot escape.\n');
fprintf(' * The Guardian is a tiny brain on the circuit board. It feels the heat,\n');
fprintf('   guesses how fast it is rising, and slows or switches off the power in time.\n\n');

fprintf(' MAIN TEST (one house)\n');
fprintf(' WITHOUT Guardian:\n');
fprintf('    hottest point reached  : %.0f %sC   -> %s\n', A.peak, deg, verdict(A, P));
fprintf('    danger (%d %sC) reached : %s\n', P.Tdanger, deg, whenStr(A.tDanger, 'never'));
fprintf('    fire risk (%d %sC)     : %s\n', P.Tfire, deg, whenStr(A.tFire, 'never'));
fprintf(' WITH Guardian:\n');
fprintf('    first warning          : %s\n', whenStr(B.tWatch, 'never'));
fprintf('    power slowed down      : %s\n', whenStr(B.tThrottle, 'not needed'));
fprintf('    power switched OFF     : %s\n', whenStr(B.tCut, 'not needed'));
fprintf('    hottest point reached  : %.0f %sC   -> %s\n', B.peak, deg, verdict(B, P));
if ~isnan(A.tDanger) && ~isnan(B.tWatch)
    fprintf('    EARLY WARNING          : %.1f minutes before the unprotected board hit danger\n', ...
            (A.tDanger - B.tWatch)/60);
end
fprintf(' HEALTHY board (no fault):\n');
fprintf('    false alarms           : %d seconds   (must be 0)\n', sum(H.state >= 2));
fprintf('    hottest point          : %.1f %sC\n\n', H.peak, deg);

fprintf(' 30 RANDOM FAULTY HOUSES (random load, room, blanket time, loose plug, noise)\n');
fprintf('    dangerous WITHOUT Guardian : %d of %d\n', MC.nDangerA, MC.nF);
fprintf('    dangerous WITH Guardian    : %d of %d\n', MC.nDangerB, MC.nF);
fprintf('    fires prevented            : %d of %d dangerous cases\n', MC.nSaved, MC.nDangerA);
fprintf('    hottest point with Guardian: %.0f %sC\n', max(MC.peakB), deg);
fprintf('    median early warning       : %.1f minutes before danger\n', MC.medLead);
fprintf('    power fully cut in         : %d houses, slowed in %d houses\n', MC.nCut, MC.nSlow);
fprintf('    10 HEALTHY houses, false alarms: %d of %d\n\n', MC.nFalse, MC.nH);

errv = abs(B.fx(6:end) - B.kf(6:end));
fprintf(' EMBEDDED CHECK  : integer-only filter vs float filter, 95%% of time within %.3f %sC (max %.3f %sC)\n', ...
        prctile95(errv), deg, max(errv), deg);
fprintf(' EMI GLITCHES    : %d bad sensor readings rejected automatically\n', B.nGate);
fprintf(' IoT             : %d packets sent instead of %d  (%.0f%% less radio use)\n', ...
        B.nSent, P.NT, 100*(1 - B.nSent/P.NT));

ok = writeFirmwareHeader(P, Fl, gain);
if ok
    fprintf(' FIRMWARE        : wrote guardian_constants.h (C code for ESP32/STM32/Arduino) in\n                   %s\n', pwd);
else
    fprintf(' FIRMWARE        : could not write guardian_constants.h here (folder is read-only).\n');
end

fprintf('\n 30-SECOND INTERVIEW PITCH:\n');
fprintf('  "I built a digital twin of a power-strip PCB in MATLAB. It models 2-D heat flow\n');
fprintf('   with I^2R feedback, a real NTC+ADC sensor chain with EMI glitches, a Kalman\n');
fprintf('   filter that I also implemented in integer-only Q15 maths for an MCU without FPU,\n');
fprintf('   CUSUM fault detection, a time-to-danger predictor and a safety state machine.\n');
fprintf('   I validated it on 30 random faulty houses: it kept %d of %d dangerous cases below\n', MC.nSaved, MC.nDangerA);
fprintf('   the danger temperature, with %d false alarms on 10 healthy houses."\n\n', MC.nFalse);

% ---------------------------------------------------------------- figures
tmin = (0:P.NT-1)'/60;
drawDashboard(P, A, B, tmin, deg);
drawEngineering(P, Fl, A, B, H, tmin, deg, gain);
drawMonteCarlo(P, MC, deg);

try
    print(1, '-dpng', '-r130', fullfile(pwd, 'ThermalGuardian_1_dashboard.png'));
    print(2, '-dpng', '-r130', fullfile(pwd, 'ThermalGuardian_2_engineering.png'));
    print(3, '-dpng', '-r130', fullfile(pwd, 'ThermalGuardian_3_random_houses.png'));
    fprintf(' Pictures saved in: %s\n', pwd);
catch
    % saving pictures is optional
end
figure(1);
fprintf('\nDONE. Look at the three figure windows.\n');
end


% =========================================================================
function P = defineParameters()
P.nr = 20;  P.nc = 30;            % PCB grid: 20 x 30 cells, 2 mm each (40 x 60 mm)
P.dt = 1;                         % time step (s)
P.NT = 2700;                      % simulated time = 45 minutes
P.C  = 0.5;                       % heat capacity per cell (J/K)
P.G  = 0.05;                      % heat conduction between cells (W/K)
P.h0 = 0.0015;                    % cooling to air per cell (W/K), normal
P.Tamb = 25;                      % room temperature (deg C)
P.I0 = 10;                        % load current (A)

P.Rgood = 0.005;                  % healthy plug contact resistance (ohm)
P.Rbad  = 0.12;                   % loose plug contact resistance (ohm)
P.tBlanket = 300;                 % blanket put on strip at t = 5 min
P.blanketCooling = 0.3;           % cooling drops to 30 percent
P.tLoose0 = 600;  P.tLoose1 = 1200;   % plug loosens between minute 10 and 20

P.mConn = false(P.nr,P.nc);  P.mConn(8:12, 2:4)   = true;   % plug / connector
P.mTrace= false(P.nr,P.nc);  P.mTrace(10, 5:27)   = true;   % copper trace
P.mMos  = false(P.nr,P.nc);  P.mMos(9:11, 14:16)  = true;   % power MOSFET
P.mSmps = false(P.nr,P.nc);  P.mSmps(14:17, 22:27)= true;   % charger section
P.sr = 10;  P.sc = 6;                                       % NTC sensor cell
P.nConn = nnz(P.mConn);  P.nMos = nnz(P.mMos);  P.nSmps = nnz(P.mSmps);

P.R25 = 1e4;  P.beta = 3950;  P.Rfix = 1e4;   % NTC 10k, beta 3950, 10k divider
P.gate = 3.0;                                  % glitch gate (deg C)

P.cusumAllow = 0.004;             % allowed heating speed (deg C per s)
P.cusumLimit = 1.5;               % CUSUM alarm level
P.Twatch = 55; P.Tthrottle = 65; P.Tcut = 75;  % guardian hot-spot thresholds
P.Tref   = 80;                    % target for countdown
P.Tdanger = 90;                   % insulation starts to fail
P.Tfire   = 110;                  % fire risk
P.hold2 = 60;  P.hold3 = 120;     % seconds to wait before relaxing (no chattering)
P.rise  = 0.002;                  % how slowly power is given back (per second)
end


% =========================================================================
function N = makeNoise(P)
N.adcNoise = 1.2*randn(P.NT,1);                      % ADC noise (LSB)
spike      = rand(P.NT,1) < 0.015;                   % 1.5 percent EMI glitches
spv        = (2*(rand(P.NT,1) < 0.5) - 1) .* (10 + 5*rand(P.NT,1));
N.spikeVal = double(spike) .* spv;
N.drop     = rand(P.NT,1) < 0.10;                    % 10 percent Wi-Fi loss
end


% =========================================================================
function Fl = designFilter(P)
dt = P.dt;
Fl.Fm = [1 dt; 0 1];
Fl.Hm = [1 0];
qa    = 0.002^2;
Fl.Rm = 0.3^2;
Fl.Qm = qa*[dt^4/4 dt^3/2; dt^3/2 dt^2];
Pc = eye(2);
K  = [0; 0];
for i = 1:2000                                % steady-state Kalman gain
    Pp = Fl.Fm*Pc*Fl.Fm' + Fl.Qm;
    Sv = Fl.Hm*Pp*Fl.Hm' + Fl.Rm;
    K  = Pp*Fl.Hm'/Sv;
    Pc = (eye(2) - K*Fl.Hm)*Pp;
end
Fl.K1  = K(1);   Fl.K2  = K(2);
Fl.K1q = round(Fl.K1*32768);                  % Q15 integer gains for the MCU
Fl.K2q = round(Fl.K2*32768);
end


% =========================================================================
function T = warmUp(P, nSteps)
T = P.Tamb*ones(P.nr, P.nc);
for k = 1:nSteps
    T = thermalStep(T, P.I0, P.Rgood, 1, P);
end
end


% =========================================================================
function g = calibrateGain(P, T0)
% Digital-twin calibration: how much hotter is the real hot spot than the
% place where the sensor sits?
T = T0;
for k = 1:4000
    T = thermalStep(T, P.I0, P.Rbad, 1, P);
end
g = (max(T(:)) - P.Tamb) / (T(P.sr,P.sc) - P.Tamb);
end


% =========================================================================
function [T, Ptot] = thermalStep(T, I, Rc, hmult, P)
% one second of heat flow on the PCB
Tp = [T(1,:); T; T(end,:)];                   % insulated edges
Tp = [Tp(:,1), Tp, Tp(:,end)];
L  = Tp(1:end-2,2:end-1) + Tp(3:end,2:end-1) + ...
     Tp(2:end-1,1:end-2) + Tp(2:end-1,3:end) - 4*T;

Pm = zeros(P.nr, P.nc);
% loose plug heats like a tiny heater: P = I^2 * R
Pm(P.mConn) = Pm(P.mConn) + I^2*Rc/P.nConn;
% copper trace: resistance GROWS with temperature (feedback)
rho   = 1.72e-8*(1 + 0.0039*(T(P.mTrace) - 20));
Rcell = rho*2e-3/(4e-3*35e-6);                % 4 mm wide, 1 oz copper, 2 mm long
Pm(P.mTrace) = Pm(P.mTrace) + I^2*Rcell;
% power MOSFET: Rds(on) also grows with temperature
Rds = 0.012*(1 + 0.006*(T(P.mMos) - 25));
Pm(P.mMos) = Pm(P.mMos) + I^2*Rds/P.nMos;
% charger electronics (always on)
Pm(P.mSmps) = Pm(P.mSmps) + 1.5/P.nSmps;

T    = T + P.dt/P.C*(P.G*L + Pm - P.h0*hmult*(T - P.Tamb));
Ptot = sum(Pm(:));
end


% =========================================================================
function Rc = contactResistance(tk, P, healthy)
if healthy || tk < P.tLoose0
    Rc = P.Rgood;
elseif tk > P.tLoose1
    Rc = P.Rbad;
else
    Rc = P.Rgood + (P.Rbad - P.Rgood)*(tk - P.tLoose0)/(P.tLoose1 - P.tLoose0);
end
end


% =========================================================================
function h = blanketFactor(tk, P, healthy)
if healthy || tk < P.tBlanket
    h = 1;
else
    h = P.blanketCooling;
end
end


% =========================================================================
function Tm = readSensor(Ts, adcNoise, spikeVal, P)
% NTC thermistor -> voltage divider -> 10-bit ADC -> back to temperature
Rn  = P.R25*exp(P.beta*(1/(Ts + 273.15) - 1/298.15));
adc = round(Rn/(Rn + P.Rfix)*1023 + adcNoise);
adc = min(max(adc, 1), 1022);
Rr  = P.Rfix*adc/(1023 - adc);
Tm  = 1/(1/298.15 + log(Rr/P.R25)/P.beta) - 273.15 + spikeVal;
end


% =========================================================================
function R = runScenario(P, Fl, N, T0, gain, guardOn, healthy)
NT = P.NT;
T = T0;  u = 1;  state = 1;  hold = 0;  cus = 0;

z0 = readSensor(T(P.sr,P.sc), 0, 0, P);
xf = [z0; 0];  Pf = eye(2);  rejF = 0;            % float Kalman filter
xq = round(z0*256);  vq = 0;  rejQ = 0;           % integer filter (Q8 / Q16)
K1q = Fl.K1q;  K2q = Fl.K2q;

lastT = z0;  lastState = 1;  lastK = 0;  nSent = 0;  nLost = 0;  nGate = 0;

R.Tpeak = zeros(NT,1);  R.Tsens = zeros(NT,1);  R.raw = zeros(NT,1);
R.kf = zeros(NT,1);     R.fx = zeros(NT,1);     R.Hs = zeros(NT,1);
R.state = zeros(NT,1);  R.u = zeros(NT,1);      R.ttl = zeros(NT,1);
R.cus = zeros(NT,1);    R.cumPkt = zeros(NT,1); R.Pplug = zeros(NT,1);

for k = 1:NT
    tk = k - 1;
    I  = P.I0*u;
    Rc = contactResistance(tk, P, healthy);
    T  = thermalStep(T, I, Rc, blanketFactor(tk,P,healthy), P);
    Ts = T(P.sr, P.sc);
    z  = readSensor(Ts, N.adcNoise(k), N.spikeVal(k), P);

    % ---- float Kalman filter (golden reference) ----
    xp  = Fl.Fm*xf;
    Pp  = Fl.Fm*Pf*Fl.Fm' + Fl.Qm;
    inn = z - xp(1);
    if abs(inn) < P.gate
        Sv = Pp(1,1) + Fl.Rm;
        Kk = Pp(:,1)/Sv;
        xf = xp + Kk*inn;
        Pf = (eye(2) - Kk*Fl.Hm)*Pp;
        rejF = 0;
    else
        xf = xp;  Pf = Pp;  rejF = rejF + 1;
        if rejF >= 10, xf = [z; 0]; Pf = eye(2); rejF = 0; end
    end

    % ---- integer-only filter (what the MCU runs) ----
    zq  = round(z*256);                          % temperature in 1/256 deg C
    xpq = xq + floor(vq/256);                    % predict   (vq in 1/65536 deg C per s)
    rq  = zq - xpq;                              % innovation
    if abs(rq) < P.gate*256
        xq = xpq + floor(K1q*rq/32768);          % >>15
        vq = vq  + floor(K2q*rq*256/32768);
        rejQ = 0;
    else
        xq = xpq;  rejQ = rejQ + 1;  nGate = nGate + 1;
        if rejQ >= 10, xq = zq; vq = 0; rejQ = 0; end
    end
    Th = xq/256;                                 % estimated sensor temp
    v  = vq/65536;                               % estimated heating speed (deg C/s)

    % ---- predictions and alarms ----
    Hs = P.Tamb + gain*(Th - P.Tamb);            % estimated HOT-SPOT temperature
    vH = gain*v;
    if vH > 0.002 && Hs > 40
        ttl = (P.Tref - Hs)/vH;                  % seconds until 80 deg C
    else
        ttl = Inf;
    end
    cus   = max(0, cus + (v - P.cusumAllow));    % CUSUM: heating faster than allowed?
    alarm = cus > P.cusumLimit;

    % ---- safety state machine (with hysteresis = no chattering) ----
    des = 1;
    if Hs >= P.Twatch    || ttl < 600 || alarm, des = 2; end
    if Hs >= P.Tthrottle || ttl < 240,          des = 3; end
    if Hs >= P.Tcut      || ttl < 60,           des = 4; end
    if des >= state
        state = des;  hold = 0;
    else
        hold = hold + 1;
        if state >= 3, need = P.hold3; else need = P.hold2; end
        if hold >= need && state < 4
            state = state - 1;  hold = 0;
        end
    end

    % ---- actuator (relay / PWM on the load) ----
    if guardOn
        if state == 4
            u = 0;                               % power OFF
        elseif state == 3
            u = max(0.35, u - 0.01);             % slow down
        elseif state == 1
            u = min(1, u + P.rise);              % give power back very slowly
        end                                      % state 2: keep power as it is
    end

    % ---- IoT: event-driven reporting ----
    if abs(Th - lastT) >= 0.5 || state ~= lastState || (k - lastK) >= 60
        nSent = nSent + 1;
        if N.drop(k), nLost = nLost + 1; end
        lastT = Th;  lastState = state;  lastK = k;
    end

    R.Tpeak(k) = max(T(:));   R.Tsens(k) = Ts;   R.raw(k) = z;
    R.kf(k) = xf(1);          R.fx(k) = Th;      R.Hs(k) = Hs;
    R.state(k) = state;       R.u(k) = u;        R.ttl(k) = ttl;
    R.cus(k) = cus;           R.cumPkt(k) = nSent;  R.Pplug(k) = I^2*Rc;
end

R.Tend = T;  R.nSent = nSent;  R.nLost = nLost;  R.nGate = nGate;
R.peak      = max(R.Tpeak);
R.tDanger   = firstSec(R.Tpeak >= P.Tdanger);
R.tFire     = firstSec(R.Tpeak >= P.Tfire);
R.tWatch    = firstSec(R.state >= 2);
R.tThrottle = firstSec(R.state >= 3);
R.tCut      = firstSec(R.state == 4);
R.tAlarm    = firstSec(R.cus > P.cusumLimit);
end


% =========================================================================
function MC = monteCarlo(P0, Fl, gain, nF, nH)
% Random houses: different load, room temperature, blanket time, how bad the
% plug is, how fast it loosens, and different sensor noise.
rng(2026, 'twister');
MC.nF = nF;  MC.nH = nH;
MC.peakA = zeros(nF,1);  MC.peakB = zeros(nF,1);
MC.leadMin = NaN(nF,1);
MC.dangerA = false(nF,1);  MC.dangerB = false(nF,1);
MC.slowB = false(nF,1);    MC.cutB = false(nF,1);
for i = 1:nF
    Ps = randomHouse(P0);
    Ns = makeNoise(Ps);
    T0 = warmUp(Ps, 2000);
    A  = runScenario(Ps, Fl, Ns, T0, gain, false, false);
    B  = runScenario(Ps, Fl, Ns, T0, gain, true,  false);
    MC.peakA(i)   = A.peak;
    MC.peakB(i)   = B.peak;
    MC.dangerA(i) = A.peak >= P0.Tdanger;
    MC.dangerB(i) = B.peak >= P0.Tdanger;
    MC.slowB(i)   = ~isnan(B.tThrottle);
    MC.cutB(i)    = ~isnan(B.tCut);
    if MC.dangerA(i) && ~isnan(B.tWatch)
        MC.leadMin(i) = (A.tDanger - B.tWatch)/60;
    end
    if mod(i,5) == 0
        fprintf('   ... %d of %d houses done\n', i, nF + nH);
    end
end
nFalse = 0;
MC.falseSec = zeros(nH,1);
for j = 1:nH
    Ps = randomHouse(P0);
    Ns = makeNoise(Ps);
    T0 = warmUp(Ps, 2000);
    Hh = runScenario(Ps, Fl, Ns, T0, gain, true, true);
    MC.falseSec(j) = sum(Hh.state >= 2);
    if MC.falseSec(j) > 0, nFalse = nFalse + 1; end
    if mod(j,5) == 0
        fprintf('   ... %d of %d houses done\n', nF + j, nF + nH);
    end
end
MC.nFalse   = nFalse;
MC.nDangerA = sum(MC.dangerA);
MC.nDangerB = sum(MC.dangerB);
MC.nSaved   = sum(MC.dangerA & ~MC.dangerB);
MC.nSlow    = sum(MC.slowB);
MC.nCut     = sum(MC.cutB);
lead = MC.leadMin(~isnan(MC.leadMin));
if isempty(lead), MC.medLead = NaN; else MC.medLead = median(lead); end
end


% =========================================================================
function Ps = randomHouse(P)
Ps = P;
Ps.I0 = 6 + 6*rand;                       % load 6 to 12 A
Ps.Tamb = 15 + 23*rand;                   % room 15 to 38 deg C
Ps.tBlanket = 900*rand;                   % blanket placed at any time
Ps.blanketCooling = 0.2 + 0.3*rand;       % blanket blocks 50 to 80 percent of cooling
Ps.tLoose0 = 300 + 900*rand;              % plug starts to loosen
Ps.tLoose1 = Ps.tLoose0 + 300 + 600*rand; % 5 to 15 minutes to become loose
Ps.Rbad = 0.05 + 0.15*rand;               % final bad contact 0.05 to 0.2 ohm
end


% =========================================================================
function s = firstSec(mask)
idx = find(mask, 1);
if isempty(idx), s = NaN; else s = idx - 1; end
end

function s = minStr(sec)
if isnan(sec), s = 'never'; else s = sprintf('%.1f', sec/60); end
end

function s = whenStr(sec, noneText)
if isnan(sec), s = noneText; else s = ['minute ' sprintf('%.1f', sec/60)]; end
end

function p = prctile95(x)
x = sort(x(:));
p = x(max(1, ceil(0.95*numel(x))));
end

function s = verdict(R, P)
if R.peak >= P.Tfire
    s = 'FIRE RISK';
elseif R.peak >= P.Tdanger
    s = 'DANGER';
else
    s = 'SAFE';
end
end


% =========================================================================
function ax = panelAxes(row, col)
% 2 x 3 grid with room on top for the big title
x0 = [0.06 0.375 0.69];
y0 = [0.56 0.08];
ax = axes('Position', [x0(col) y0(row) 0.24 0.30]);
end


% =========================================================================
function drawDashboard(P, A, B, tmin, deg)
fig = figure(1);
set(fig, 'Name', 'Thermal Guardian - 1 Dashboard', 'NumberTitle', 'off', ...
    'Color', 'w', 'Units', 'normalized', 'Position', [0.02 0.05 0.96 0.88], ...
    'DefaultAxesFontSize', 9);
tmax  = tmin(end);
green = [0 0.55 0.1];
lbl   = ['Temperature (' deg 'C)'];

% ---- 1 hottest spot
panelAxes(1,1);
ymax = min(max(A.Tpeak)*1.05, 200);
patch([0 tmax tmax 0], [20 20 P.Twatch P.Twatch], [0.86 1 0.86], 'EdgeColor', 'none'); hold on;
patch([0 tmax tmax 0], [P.Twatch P.Twatch P.Tdanger P.Tdanger], [1 1 0.8], 'EdgeColor', 'none');
patch([0 tmax tmax 0], [P.Tdanger P.Tdanger ymax ymax], [1 0.86 0.86], 'EdgeColor', 'none');
h1 = plot(tmin, A.Tpeak, 'r', 'LineWidth', 2);
h2 = plot(tmin, B.Tpeak, 'Color', green, 'LineWidth', 2);
text(tmax, 38, 'safe zone', 'HorizontalAlignment', 'right', 'Color', [0 0.4 0], 'FontSize', 8);
text(tmax, 72, 'warm zone', 'HorizontalAlignment', 'right', 'Color', [0.5 0.4 0], 'FontSize', 8);
text(tmax, P.Tdanger + 8, 'DANGER zone', 'HorizontalAlignment', 'right', 'Color', [0.7 0 0], 'FontSize', 8, 'FontWeight', 'bold');
if ~isnan(A.tDanger)
    plot(A.tDanger/60, P.Tdanger, 'ro', 'MarkerFaceColor', 'r');
    text(A.tDanger/60 - 0.8, P.Tdanger + 14, 'danger!', 'Color', 'r', 'HorizontalAlignment', 'right', 'FontSize', 8);
end
if ~isnan(B.tThrottle)
    yy = B.Tpeak(round(B.tThrottle) + 1);
    plot(B.tThrottle/60, yy, 'o', 'Color', green, 'MarkerFaceColor', green);
    text(B.tThrottle/60 + 0.8, yy + 10, 'Guardian slows power', 'Color', green, 'FontSize', 8);
end
xlim([0 tmax]);  ylim([20 ymax]);
xlabel('Time (minutes)'); ylabel(lbl);
legend([h1 h2], {'Without Guardian', 'With Guardian'}, 'Location', 'northwest');
title({'1. How hot does the board get?', 'lower line = safer'}, 'FontSize', 10);

% ---- 2 and 3 heat pictures
cl  = [P.Tamb, max(A.Tend(:))];
ax2 = panelAxes(1,2);
drawBoard(ax2, A.Tend, cl, P);
title({'2. Board picture WITHOUT Guardian', sprintf('end of test, hottest %.0f %sC', max(A.Tend(:)), deg)}, 'FontSize', 10);
ax3 = panelAxes(1,3);
drawBoard(ax3, B.Tend, cl, P);
title({'3. Board picture WITH Guardian', sprintf('same colours, hottest %.0f %sC', max(B.Tend(:)), deg)}, 'FontSize', 10);

% ---- 4 the brain
panelAxes(2,1);
plot(tmin, B.raw, '.', 'Color', [0.65 0.65 0.65], 'MarkerSize', 4); hold on;
h5 = plot(tmin, B.Tsens, 'k--', 'LineWidth', 1);
h6 = plot(tmin, B.fx, 'b', 'LineWidth', 1.8);
xlim([0 tmax]); grid on;
ylim([floor(min(B.raw)) - 2, ceil(max(B.raw)) + 2]);
xlabel('Time (minutes)'); ylabel(lbl);
legend([h5 h6], {'Real temperature', 'Guardian belief'}, 'Location', 'northwest');
title({'4. Guardian cleans a noisy sensor', 'grey dots = bad data, blue = what it believes'}, 'FontSize', 10);

% ---- 5 traffic light
ax5 = panelAxes(2,2);
imagesc(tmin, [0 1], [B.state'; B.state']);
set(ax5, 'YDir', 'normal');
colormap(ax5, [0 0.7 0.2; 1 0.85 0; 1 0.5 0; 0.85 0 0]);
caxis([0.5 4.5]); hold on;
plot(tmin, B.u, 'k', 'LineWidth', 2.5);
ylim([0 1]); xlim([0 tmax]);
text(tmax*0.98, 0.06, 'black line = power given to load', 'HorizontalAlignment', 'right', ...
     'BackgroundColor', 'w', 'FontSize', 8, 'Interpreter', 'none');
xlabel('Time (minutes)'); ylabel('Power to load (1 = full)');
title({'5. Guardian traffic light', 'green safe, yellow watch, orange slowing, red OFF'}, 'FontSize', 10);

% ---- 6 plain-language story
ax6 = panelAxes(2,3);
set(ax6, 'Visible', 'off', 'XLim', [0 1], 'YLim', [0 1]);
txt = { ...
 'WHAT HAPPENED IN THIS TEST?', ...
 'A power strip is under a blanket, so', ...
 'it cannot cool down. Its plug slowly', ...
 'gets loose, and a loose plug turns', ...
 'into a little heater.', ...
 '', ...
 'WITHOUT Guardian', ...
 sprintf('  hottest: %.0f %sC -> %s', A.peak, deg, verdict(A, P)), ...
 ['  danger at: ' whenStr(A.tDanger, 'never')], ...
 '', ...
 'WITH Guardian', ...
 ['  first warning: ' whenStr(B.tWatch, 'never')], ...
 ['  power slowed : ' whenStr(B.tThrottle, 'not needed')], ...
 ['  power OFF    : ' whenStr(B.tCut, 'not needed')], ...
 sprintf('  hottest: %.0f %sC -> %s', B.peak, deg, verdict(B, P)), ...
 '', ...
 'IDEA: feel the heat, guess how fast', ...
 'it grows, act BEFORE it is dangerous.'};
text(0.0, 1.05, txt, 'Parent', ax6, 'VerticalAlignment', 'top', ...
     'FontSize', 10, 'Interpreter', 'none', 'FontName', 'FixedWidth');

annotation('textbox', [0.05 0.935 0.9 0.055], 'String', ...
    'PCB THERMAL GUARDIAN  -  predicts and prevents electrical fires in power strips and chargers', ...
    'EdgeColor', 'none', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
    'FontSize', 14, 'FontWeight', 'bold', 'Interpreter', 'none');
drawnow;
end


% =========================================================================
function drawBoard(ax, Tend, cl, P)
axes(ax);
imagesc(Tend);
colormap(ax, jet(256));
caxis(cl);
axis equal tight;
set(ax, 'XTick', [], 'YTick', []);
cb = colorbar;
cb.Label.String = 'deg C';
hold on;
% outlines of the real parts
rectangle('Position', [1.5 7.5 3 5],  'EdgeColor', 'w', 'LineWidth', 1.5);   % plug
rectangle('Position', [13.5 8.5 3 3], 'EdgeColor', 'w', 'LineWidth', 1);     % MOSFET
rectangle('Position', [21.5 13.5 6 4], 'EdgeColor', 'w', 'LineWidth', 1);    % charger
plot([4.5 27.5], [10 10], 'w:', 'LineWidth', 1);                              % copper trace
plot(P.sc, P.sr, 'ks', 'MarkerFaceColor', 'w', 'MarkerSize', 6);             % sensor
lab(1.0, 5.8,  'PLUG');
lab(4.5, 14.5, 'sensor');
lab(13.0, 6.8, 'MOSFET');
lab(21.5, 12.2, 'CHARGER');
lab(9.0, 8.4,  'copper trace');
end

function lab(x, y, s)
text(x, y, s, 'Color', 'w', 'BackgroundColor', 'k', 'Margin', 1, ...
     'FontSize', 7.5, 'FontWeight', 'bold', 'Interpreter', 'none');
end


% =========================================================================
function drawEngineering(P, Fl, A, B, H, tmin, deg, gain)
fig = figure(2);
set(fig, 'Name', 'Thermal Guardian - 2 Engineering deep dive', 'NumberTitle', 'off', ...
    'Color', 'w', 'Units', 'normalized', 'Position', [0.04 0.04 0.92 0.86], ...
    'DefaultAxesFontSize', 9);
tmax = tmin(end);

% ---- A IPC-2221
panelAxes(1,1);
Iv  = linspace(1, 20, 100);
dTs = [10 20 40];
cols = {[0 0.45 0.9], [0 0.6 0.2], [0.9 0.4 0]};
hh = zeros(1,4);
for d = 1:3
    Amil = (Iv./(0.048*dTs(d)^0.44)).^(1/0.725);     % IPC-2221, outer layer
    wmm  = Amil/1.378*0.0254;                        % 1 oz copper
    hh(d) = plot(Iv, wmm, 'Color', cols{d}, 'LineWidth', 2); hold on;
end
wDes  = 4;
Ades  = wDes/0.0254*1.378;
dTdes = (P.I0/(0.048*Ades^0.725))^(1/0.44);
hh(4) = plot(P.I0, wDes, 'ko', 'MarkerFaceColor', 'y', 'MarkerSize', 10);
grid on; xlabel('Current (A)'); ylabel('Trace width needed (mm)');
legend(hh, {['allow ' num2str(dTs(1)) ' ' deg 'C rise'], ['allow ' num2str(dTs(2)) ' ' deg 'C rise'], ...
        ['allow ' num2str(dTs(3)) ' ' deg 'C rise'], sprintf('ours: %.0f %sC rise', dTdes, deg)}, ...
        'Location', 'northwest');
title({'A. Is the copper trace thick enough?', 'yes - the plug is the problem, not the trace'}, 'FontSize', 10);

% ---- B float vs fixed
panelAxes(1,2);
errv = abs(B.fx - B.kf);
plot(tmin(6:end), errv(6:end), 'b'); grid on; xlim([0 tmax]);
xlabel('Time (minutes)'); ylabel(['Difference (' deg 'C)']);
title({'B. Cheap-chip maths = PC maths', sprintf('integer vs float: within %.2f %sC (95%% of time)', ...
       prctile95(errv(6:end)), deg)}, 'FontSize', 10);

% ---- C IoT packets
panelAxes(1,3);
h7 = plot(tmin, (1:P.NT)', 'r', 'LineWidth', 2); hold on;
h8 = plot(tmin, B.cumPkt, 'Color', [0 0.6 0.1], 'LineWidth', 2);
grid on; xlim([0 tmax]);
xlabel('Time (minutes)'); ylabel('Wi-Fi packets sent (total)');
legend([h7 h8], {'send every second', 'Guardian: only when it matters'}, 'Location', 'northwest');
title({'C. Fewer messages, same safety', sprintf('%.0f%% fewer Wi-Fi packets', ...
       100*(1 - B.nSent/P.NT))}, 'FontSize', 10);

% ---- D early-warning alarm
panelAxes(2,1);
cc = min(A.cus, 10);
plot(tmin, cc, 'm', 'LineWidth', 2); hold on;
plot([0 tmax], [P.cusumLimit P.cusumLimit], 'k--');
if ~isnan(A.tAlarm)
    plot([A.tAlarm A.tAlarm]/60, [0 10], '--', 'Color', [0.6 0 0.6]);
    text(A.tAlarm/60 + 0.5, 8.8, 'ALARM', 'Color', [0.6 0 0.6], 'FontSize', 8, 'FontWeight', 'bold');
end
if ~isnan(A.tDanger)
    plot([A.tDanger A.tDanger]/60, [0 10], 'r--');
    text(A.tDanger/60 + 0.5, 5.5, 'danger (no Guardian)', 'Color', 'r', 'FontSize', 8);
end
grid on; xlim([0 tmax]); ylim([0 10]);
xlabel('Time (minutes)'); ylabel('Heating-too-fast score');
title({'D. Early-warning alarm', sprintf('alarm at minute %s, danger would be at %s', ...
       minStr(A.tAlarm), minStr(A.tDanger))}, 'FontSize', 10);

% ---- E plug heater
panelAxes(2,2);
h9  = plot(tmin, A.Pplug, 'r', 'LineWidth', 2); hold on;
h10 = plot(tmin, B.Pplug, 'Color', [0 0.55 0.1], 'LineWidth', 2);
grid on; xlim([0 tmax]);
xlabel('Time (minutes)'); ylabel('Heat inside the plug (watts)');
legend([h9 h10], {'without Guardian', 'with Guardian'}, 'Location', 'northwest');
title({'E. A loose plug becomes a heater', 'watts burned inside the plug (I^2 x R)'}, 'FontSize', 10);

% ---- F scoreboard
ax6 = panelAxes(2,3);
set(ax6, 'Visible', 'off', 'XLim', [0 1], 'YLim', [0 1]);
errv2 = errv(6:end);
txt = { ...
 'SCOREBOARD (main test)', ...
 '', ...
 'Healthy board, 45 minutes', ...
 sprintf('  false alarms: %d  (target 0)', sum(H.state >= 2)), ...
 sprintf('  hottest: %.1f %sC', H.peak, deg), ...
 '', ...
 'Fault, NO Guardian', ...
 sprintf('  hottest: %.0f %sC -> %s', A.peak, deg, verdict(A, P)), ...
 'Fault, WITH Guardian', ...
 sprintf('  hottest: %.0f %sC -> %s', B.peak, deg, verdict(B, P)), ...
 '', ...
 'Embedded', ...
 sprintf('  glitches rejected : %d', B.nGate), ...
 sprintf('  int vs float, max : %.2f %sC', max(errv2), deg), ...
 sprintf('  Q15 gains         : %d, %d', Fl.K1q, Fl.K2q), ...
 sprintf('  hot spot / sensor : %.2f x', gain), ...
 'IoT', ...
 sprintf('  packets %d of %d', B.nSent, P.NT)};
text(0.0, 1.05, txt, 'Parent', ax6, 'VerticalAlignment', 'top', ...
     'FontSize', 10, 'Interpreter', 'none', 'FontName', 'FixedWidth');

annotation('textbox', [0.05 0.935 0.9 0.055], 'String', ...
    'ENGINEERING DEEP DIVE  -  PCB design check, embedded maths, IoT, validation', ...
    'EdgeColor', 'none', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
    'FontSize', 14, 'FontWeight', 'bold', 'Interpreter', 'none');
drawnow;
end


% =========================================================================
function drawMonteCarlo(P, MC, deg)
fig = figure(3);
set(fig, 'Name', 'Thermal Guardian - 3 Random houses test', 'NumberTitle', 'off', ...
    'Color', 'w', 'Units', 'normalized', 'Position', [0.06 0.05 0.88 0.86], ...
    'DefaultAxesFontSize', 9);
n = MC.nF;
x = (1:n)';
ycap = 200;

% ---- hottest point of every house
axes('Position', [0.07 0.56 0.58 0.30]);
patch([0 n+1 n+1 0], [0 0 P.Tdanger P.Tdanger], [0.86 1 0.86], 'EdgeColor', 'none'); hold on;
patch([0 n+1 n+1 0], [P.Tdanger P.Tdanger ycap ycap], [1 0.86 0.86], 'EdgeColor', 'none');
plot(x, min(MC.peakA, ycap), 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 7);
plot(x, MC.peakB, 'o', 'Color', [0 0.5 0.1], 'MarkerFaceColor', [0 0.75 0.2], 'MarkerSize', 7);
plot([0 n+1], [P.Tdanger P.Tdanger], '--', 'Color', [1 0.5 0], 'LineWidth', 1.5);
text(n+0.5, P.Tdanger + 8, 'DANGER above this line', 'HorizontalAlignment', 'right', ...
     'Color', [0.7 0 0], 'FontSize', 8, 'FontWeight', 'bold');
xlim([0 n+1]); ylim([0 ycap]);
xlabel('House number (each house is different)');
ylabel(['Hottest point (' deg 'C, capped at ' num2str(ycap) ')']);
title({'Each dot = one random house.  RED = without Guardian,  GREEN = with Guardian', ...
       'green dots staying under the line = Guardian worked'}, 'FontSize', 10);

% ---- early warning
axes('Position', [0.07 0.08 0.58 0.30]);
bar(x, MC.leadMin, 0.6, 'FaceColor', [0.2 0.5 0.9]);
grid on; xlim([0 n+1]);
xlabel('House number (empty = that fault never got dangerous)');
ylabel('Minutes of warning');
title({'How early did the Guardian warn?', 'minutes before the unprotected board would reach danger'}, 'FontSize', 10);

% ---- verdict
ax3 = axes('Position', [0.69 0.08 0.29 0.78]);
set(ax3, 'Visible', 'off', 'XLim', [0 1], 'YLim', [0 1]);
nHarmless = MC.nF - MC.nDangerA;
nuis = sum(~MC.dangerA & MC.slowB);
txt = { ...
 'RESULT OF THE RANDOM TEST', ...
 '', ...
 'Random in every house:', ...
 '  load 6 to 12 A, room 15 to 38 C', ...
 '  blanket at any time, plug fault', ...
 '  0.05 to 0.2 ohm, different noise', ...
 '', ...
 sprintf('%d FAULTY houses', MC.nF), ...
 sprintf('  dangerous WITHOUT Guardian: %d', MC.nDangerA), ...
 sprintf('  dangerous WITH Guardian   : %d', MC.nDangerB), ...
 sprintf('  fires prevented: %d of %d', MC.nSaved, MC.nDangerA), ...
 sprintf('  hottest with Guardian: %.0f %sC', max(MC.peakB), deg), ...
 sprintf('  median early warning: %.1f min', MC.medLead), ...
 sprintf('  power slowed: %d houses', MC.nSlow), ...
 sprintf('  power cut OFF: %d houses', MC.nCut), ...
 sprintf('  harmless faults: %d (slowed anyway: %d)', nHarmless, nuis), ...
 '', ...
 sprintf('%d HEALTHY houses', MC.nH), ...
 sprintf('  false alarms: %d of %d', MC.nFalse, MC.nH), ...
 '', ...
 'Honest note: this is a simulation.', ...
 'Real boards need thermal-camera', ...
 'calibration before selling.'};
text(0.0, 1.0, txt, 'Parent', ax3, 'VerticalAlignment', 'top', ...
     'FontSize', 10, 'Interpreter', 'none', 'FontName', 'FixedWidth');

annotation('textbox', [0.05 0.935 0.9 0.055], 'String', ...
    'RANDOM-HOUSE TEST  -  does the Guardian work in 40 different situations?', ...
    'EdgeColor', 'none', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
    'FontSize', 14, 'FontWeight', 'bold', 'Interpreter', 'none');
drawnow;
end


% =========================================================================
function ok = writeFirmwareHeader(P, Fl, gain)
ok = false;
try
    fid = fopen(fullfile(pwd, 'guardian_constants.h'), 'w');
    if fid < 0, return; end
    L = { ...
     '/* guardian_constants.h - generated by ThermalGuardian.m */', ...
     '/* Integer-only thermal guardian for MCUs without FPU (ESP32, STM32, AVR). */', ...
     '#include <stdint.h>', ...
     '', ...
     sprintf('#define KF_K1_Q15        %d     /* position gain, Q15 */', Fl.K1q), ...
     sprintf('#define KF_K2_Q15        %d       /* rate gain, Q15 */', Fl.K2q), ...
     sprintf('#define GATE_Q8          %d     /* glitch gate = %.1f C in 1/256 C */', round(P.gate*256), P.gate), ...
     sprintf('#define HOTSPOT_GAIN_Q8  %d     /* hot spot / sensor ratio x256 */', round(gain*256)), ...
     sprintf('#define T_AMBIENT_Q8     %d', round(P.Tamb*256)), ...
     sprintf('#define T_WATCH_C        %d', P.Twatch), ...
     sprintf('#define T_THROTTLE_C     %d', P.Tthrottle), ...
     sprintf('#define T_CUTOFF_C       %d', P.Tcut), ...
     sprintf('#define HOLD_WATCH_S     %d     /* wait before relaxing, no chattering */', P.hold2), ...
     sprintf('#define HOLD_SLOW_S      %d', P.hold3), ...
     '', ...
     'static int32_t x_q8 = 0;    /* temperature, 1/256 C       */', ...
     'static int32_t v_q16 = 0;   /* heating speed, 1/65536 C/s */', ...
     '', ...
     '/* call once per second with the ADC temperature converted to 1/256 C */', ...
     'static inline void guardian_update(int32_t z_q8)', ...
     '{', ...
     '    int32_t xp = x_q8 + (v_q16 >> 8);', ...
     '    int32_t r  = z_q8 - xp;', ...
     '    if (r < GATE_Q8 && r > -GATE_Q8) {', ...
     '        x_q8  = xp + ((KF_K1_Q15 * r) >> 15);', ...
     '        v_q16 = v_q16 + ((KF_K2_Q15 * r * 256) >> 15);', ...
     '    } else {', ...
     '        x_q8 = xp;           /* reject EMI glitch */', ...
     '    }', ...
     '}'};
    for i = 1:numel(L)
        fprintf(fid, '%s\n', L{i});
    end
    fclose(fid);
    ok = true;
catch
    ok = false;
end
end
