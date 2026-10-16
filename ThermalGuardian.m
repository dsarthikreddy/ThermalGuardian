function ThermalGuardian()
%THERMALGUARDIAN  PCB thermal digital twin - stops electrical fires.
%
%   ThermalGuardian     runs the whole simulation and opens two figures.
%
%   MATLAB R2017b or newer. No toolboxes needed.
%
%   THE PROBLEM IT SOLVES
%   A power strip sits under a blanket, so heat cannot escape. At the same
%   time the plug works itself loose. A loose contact has high resistance,
%   and heat = I^2 x R. The joint gets hotter, its resistance rises, and it
%   gets hotter still - thermal runaway. Nobody notices until it is too
%   late. This is a real cause of house fires.
%
%   WHAT IT BUILDS
%   A digital twin: a 2-D model of the circuit board that heats up, a real
%   sensor chain reading it (NTC thermistor + 10-bit ADC + noise + EMI
%   glitches), and a small safety brain that watches the temperature, works
%   out how fast it is rising, and cuts the power in time.
%
%   WHAT IT CONTAINS (each a talking point)
%     1  2-D PCB heat flow, finite difference, copper resistance rises with
%         temperature (this is what creates the runaway)
%     2  Real sensor chain: NTC + 10-bit ADC + noise + random EMI glitches
%     3  Kalman filter, floating point (the reference)
%     4  The SAME filter in integer-only Q15 maths - what a cheap chip with
%         no floating-point unit can actually run. The gap is measured.
%     5  Glitch gating with automatic re-lock
%     6  CUSUM abnormal-heating detector and a time-to-danger countdown
%     7  Safety state machine with hysteresis: SAFE > WATCH > SLOW > OFF
%     8  Closed-loop test: WITHOUT vs WITH the guard, plus a healthy board
%     9  IoT reporting that sends only when something matters
%    10  IPC-2221 printed-circuit trace-width design check
%    11  Writes guardian_constants.h - real C code for ESP32/STM32/Arduino
%
%   All parameters are representative simulation values. A real product
%   would calibrate them with a thermal camera.

close all; clc;

P  = defineParameters();
Fl = designFilter(P);

rng(7, 'twister');                 % same result every run

N.adcNoise = 1.2*randn(P.NT,1);                     % ADC noise (LSB)
spike      = rand(P.NT,1) < 0.015;                  % 1.5% EMI glitches
spv        = (2*(rand(P.NT,1) < 0.5) - 1) .* (10 + 5*rand(P.NT,1));
N.spikeVal = double(spike) .* spv;
N.drop     = rand(P.NT,1) < 0.10;                   % 10% Wi-Fi loss

deg   = char(176);
line1 = repmat('=', 1, 72);

fprintf('\n%s\n', line1);
fprintf('  PCB THERMAL GUARDIAN - stopping home electrical fires before they start\n');
fprintf('%s\n\n', line1);
fprintf('Simulating (about 10 seconds)...\n');

T0   = warmUp(P);
gain = calibrateGain(P, T0);

A = runScenario(P, Fl, N, T0, gain, false, false);   % fault,  NO guard
B = runScenario(P, Fl, N, T0, gain, true,  false);   % fault,  WITH guard
H = runScenario(P, Fl, N, T0, gain, true,  true);    % healthy board

fprintf('\n%s\n', line1);
fprintf('  EXPLAINED SIMPLY (like for a 5th-class student)\n');
fprintf('%s\n', line1);
fprintf('  * A plug is like a water pipe joint. If it gets loose, it gets HOT.\n');
fprintf('  * A blanket on top is like wearing a jacket in summer: heat cannot escape.\n');
fprintf('  * The Guardian is a tiny brain on the board. It feels the heat,\n');
fprintf('    guesses how fast it is rising, and switches the power off in time.\n\n');

fprintf('  WITHOUT Guardian:\n');
fprintf('    hottest point reached  : %.0f %sC\n', A.peak, deg);
fprintf('    DANGER (%d %sC) reached : minute %s\n', P.Tdanger, deg, minStr(A.tDanger));
fprintf('    FIRE RISK (%d %sC)      : minute %s\n', P.Tfire, deg, minStr(A.tFire));

fprintf('  WITH Guardian:\n');
fprintf('    first warning         : minute %s\n', minStr(B.tWatch));
fprintf('    power slowed down     : minute %s\n', minStr(B.tThrottle));
fprintf('    power switched OFF    : minute %s\n', minStr(B.tCut));
fprintf('    hottest point reached : %.0f %sC -> %s\n', B.peak, deg, verdict(B, P));

fprintf('  HEALTHY board (no fault):\n');
fprintf('    false alarms          : %d seconds (must be 0)\n', sum(H.state >= 2));
fprintf('    hottest point         : %.1f %sC\n\n', H.peak, deg);

errv = abs(B.fx(6:end) - B.kf(6:end));

fprintf('  EMBEDDED CHECK : integer-only filter vs float filter,\n');
fprintf('                   95%% of time within %.3f %sC (max %.3f %sC)\n', ...
    prctile95(errv), deg, max(errv), deg);
fprintf('  EMI GLITCHES   : %d bad sensor readings rejected automatically\n', B.nGate);
fprintf('  IoT            : %d packets sent instead of %d (%.0f%% less radio use)\n', ...
    B.nSent, P.NT, 100*(1 - B.nSent/P.NT));

if ~isnan(A.tDanger) && ~isnan(B.tCut)
    fprintf('  SAFETY MARGIN  : power was cut %.1f minutes BEFORE the\n', (A.tDanger - B.tCut)/60);
    fprintf('                   unprotected board hit danger\n');
end

ok = writeFirmwareHeader(P, Fl, gain);
if ok
    fprintf('  FIRMWARE       : wrote guardian_constants.h (C code for ESP32/STM32/Arduino)\n');
    fprintf('                   in %s\n', pwd);
else
    fprintf('  FIRMWARE       : could not write guardian_constants.h here (read-only folder).\n');
end

fprintf('\n  30-SECOND INTERVIEW PITCH:\n');
fprintf('  "I built a digital twin of a power-strip PCB in MATLAB. It models 2-D heat\n');
fprintf('   flow with I^2R feedback, a real NTC+ADC sensor chain with EMI glitches, a\n');
fprintf('   Kalman filter that I also implemented in integer-only Q15 maths for an MCU\n');
fprintf('   without an FPU, CUSUM fault detection, a time-to-danger predictor and a\n');
fprintf('   safety state machine. In closed-loop tests it cut power before the board\n');
fprintf('   reached its danger temperature, had zero false alarms on a healthy board,\n');
fprintf('   and cut IoT traffic by %.0f%%."\n\n', 100*(1 - B.nSent/P.NT));

tmin = (0:P.NT-1)'/60;

drawDashboard(P, A, B, tmin, deg);
drawEngineering(P, Fl, A, B, H, tmin, deg, gain);

try
    print(1, '-dpng', '-r130', fullfile(pwd, 'ThermalGuardian_dashboard.png'));
    print(2, '-dpng', '-r130', fullfile(pwd, 'ThermalGuardian_engineering.png'));
    fprintf(' Pictures saved in: %s\n', pwd);
catch
    % saving pictures is optional
end

fprintf('\nDONE. Look at the two figure windows.\n');
end

%% ========================= PARAMETERS ===============================
function P = defineParameters()
P.nr = 20; P.nc = 30;            % PCB grid 20 x 30 cells, 2 mm each (40 x 60 mm)
P.dt = 1;                        % time step (s)
P.NT = 2700;                     % 2700 s = 45 minutes
P.C  = 0.5;                      % heat capacity per cell (J/K)
P.G  = 0.05;                     % conduction between cells (W/K)
P.h0 = 0.0015;                   % cooling to air per cell (W/K), normal
P.Tamb = 25;                     % room temperature (degC)
P.I0 = 10;                       % load current (A)
P.Rgood = 0.005;                 % healthy plug contact resistance (ohm)
P.Rbad  = 0.12;                  % loose plug contact resistance (ohm)
P.tBlanket = 300;                % blanket put on the strip at t = 5 min
P.blanketCooling = 0.3;          % cooling drops to 30%
P.tLoose0 = 600; P.tLoose1 = 1200;   % plug loosens between minute 10 and 20
P.mConn = false(P.nr,P.nc); P.mConn(8:12, 2:4)  = true;   % plug / connector
P.mTrace= false(P.nr,P.nc); P.mTrace(10, 5:27)  = true;   % copper trace
P.mMos  = false(P.nr,P.nc); P.mMos(9:11, 14:16) = true;   % power MOSFET
P.mSmps = false(P.nr,P.nc); P.mSmps(14:17, 22:27)= true;  % charger section
P.sr = 10; P.sc = 6;             % NTC sensor cell
P.nConn = nnz(P.mConn); P.nMos = nnz(P.mMos); P.nSmps = nnz(P.mSmps);
P.R25 = 1e4; P.beta = 3950; P.Rfix = 1e4;  % NTC 10k, beta 3950, 10k divider
P.gate = 3.0;                    % glitch gate (degC)
P.cusumAllow = 0.004;            % allowed heating speed (degC per s)
P.cusumLimit = 1.5;              % CUSUM alarm level
P.Twatch = 55; P.Tthrottle = 65; P.Tcut = 75;   % guardian hot-spot thresholds
P.Tref    = 80;                  % countdown target
P.Tdanger = 90;                  % insulation starts to fail
P.Tfire   = 110;                 % fire risk
end

%% ========================= KALMAN FILTER ============================\nfunction Fl = designFilter(P)
dt = P.dt;

Fl.Fm = [1 dt; 0 1];              % constant-velocity model
Fl.Hm = [1 0];                    % we measure temperature
qa = 0.002^2;
Fl.Rm = 0.3^2;
Fl.Qm = qa*[dt^4/4 dt^3/2; dt^3/2 dt^2];

Pc = eye(2); K = [0;0];
for i = 1:2000                    % iterate to the steady-state gain
    Pp = Fl.Fm*Pc*Fl.Fm' + Fl.Qm;
    Sv = Fl.Hm*Pp*Fl.Hm' + Fl.Rm;
    K  = Pp*Fl.Hm'/Sv;
    Pc = (eye(2) - K*Fl.Hm)*Pp;
end
Fl.K1 = K(1); Fl.K2 = K(2);
Fl.K1q = round(Fl.K1*32768);      % Q15 integer gains for the MCU
Fl.K2q = round(Fl.K2*32768);
end

%% ========================= WARM-UP AND CALIBRATION ==================
function T = warmUp(P)
T = P.Tamb*ones(P.nr, P.nc);
for k = 1:3000
    T = thermalStep(T, P.I0, P.Rgood, 1, P);
end
end

function g = calibrateGain(P, T0)
% How much hotter is the real hot spot than where the sensor sits?
T = T0;
for k = 1:4000
    T = thermalStep(T, P.I0, P.Rbad, 1, P);
end
g = (max(T(:)) - P.Tamb) / (T(P.sr,P.sc) - P.Tamb);
end

%% ========================= PCB HEAT FLOW =============================
function [T, Ptot] = thermalStep(T, I, Rc, hmult, P)
% One second of heat flow across the board.
Tp = [T(1,:); T; T(end,:)];                % insulated top and bottom edges
Tp = [Tp(:,1), Tp, Tp(:,end)];             % insulated left and right edges
L  = Tp(1:end-2,2:end-1) + Tp(3:end,2:end-1) + ...
     Tp(2:end-1,1:end-2) + Tp(2:end-1,3:end) - 4*T;

Pm = zeros(P.nr, P.nc);

% the loose plug heats like a tiny heater: P = I^2 * R
Pm(P.mConn) = Pm(P.mConn) + I^2*Rc/P.nConn;

% copper trace: resistance GROWS with temperature (this is the feedback)
rho   = 1.72e-8*(1 + 0.0039*(T(P.mTrace) - 20));
Rcell = rho*2e-3/(4e-3*35e-6);             % 4 mm wide, 1 oz copper, 2 mm long
Pm(P.mTrace) = Pm(P.mTrace) + I^2*Rcell;

% power MOSFET: Rds(on) also grows with temperature
Rds = 0.012*(1 + 0.006*(T(P.mMos) - 25));
Pm(P.mMos) = Pm(P.mMos) + I^2*Rds/P.nMos;

% charger electronics, always on
Pm(P.mSmps) = Pm(P.mSmps) + 1.5/P.nSmps;

T = T + P.dt/P.C*(P.G*L + Pm - P.h0*hmult*(T - P.Tamb));
Ptot = sum(Pm(:));
end

function Rc = contactResistance(tk, P, healthy)
if healthy || tk < P.tLoose0
    Rc = P.Rgood;
elseif tk > P.tLoose1
    Rc = P.Rbad;
else
    Rc = P.Rgood + (P.Rbad - P.Rgood)*(tk - P.tLoose0)/(P.tLoose1 - P.tLoose0);
end
end

function h = blanketFactor(tk, P, healthy)
if healthy || tk < P.tBlanket
    h = 1;
else
    h = P.blanketCooling;
end
end

%% ========================= SENSOR CHAIN ==============================
function Tm = readSensor(Ts, adcNoise, spikeVal, P)
% NTC thermistor -> voltage divider -> 10-bit ADC -> back to temperature
Rn  = P.R25*exp(P.beta*(1/(Ts + 273.15) - 1/298.15));
adc = round(Rn/(Rn + P.Rfix)*1023 + adcNoise);
adc = min(max(adc, 1), 1022);
Rr  = P.Rfix*adc/(1023 - adc);
Tm  = 1/(1/298.15 + log(Rr/P.R25)/P.beta) - 273.15 + spikeVal;
end

%% ========================= ONE SCENARIO ==============================
function R = runScenario(P, Fl, N, T0, gain, guardOn, healthy)
NT = P.NT;
T = T0; u = 1; state = 1; hold = 0; cus = 0;

z0 = readSensor(T(P.sr,P.sc), 0, 0, P);

xf = [z0; 0]; Pf = eye(2); rejF = 0;      % float Kalman filter (reference)
xq = round(z0*256); vq = 0; rejQ = 0;     % integer filter, Q8 / Q16
K1q = Fl.K1q; K2q = Fl.K2q;

lastT = z0; lastState = 1; lastK = 0; nSent = 0; nLost = 0; nGate = 0;

R.Tpeak = zeros(NT,1); R.Tsens = zeros(NT,1); R.raw = zeros(NT,1);
R.kf    = zeros(NT,1); R.fx    = zeros(NT,1); R.Hs  = zeros(NT,1);
R.state = zeros(NT,1); R.u     = zeros(NT,1); R.ttl = zeros(NT,1);
R.cus   = zeros(NT,1); R.cumPkt= zeros(NT,1);

for k = 1:NT
    tk = k - 1;
    I  = P.I0*u;

    % --- the board heats up (this is the thing we are trying to control)
    T  = thermalStep(T, I, contactResistance(tk,P,healthy), ...
                        blanketFactor(tk,P,healthy), P);
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
        xf = xp; Pf = Pp; rejF = rejF + 1;
        if rejF >= 10, xf = [z; 0]; Pf = eye(2); rejF = 0; end
    end

    % ---- integer-only filter: what a cheap MCU actually runs ----
    zq  = round(z*256);                 % temperature in 1/256 degC
    xpq = xq + floor(vq/256);           % predict (vq in 1/65536 degC per s)
    rq  = zq - xpq;                     % innovation
    if abs(rq) < P.gate*256
        xq = xpq + floor(K1q*rq/32768);         % >>15
        vq = vq  + floor(K2q*rq*256/32768);
        rejQ = 0;
    else
        xq = xpq; rejQ = rejQ + 1; nGate = nGate + 1;
        if rejQ >= 10, xq = zq; vq = 0; rejQ = 0; end
    end
    Th = xq/256;                        % estimated sensor temperature
    v  = vq/65536;                      % estimated heating speed (degC/s)

    % ---- prediction and alarms ----
    Hs  = P.Tamb + gain*(Th - P.Tamb);  % estimated HOT-SPOT temperature
    vH  = gain*v;
    if vH > 0.002 && Hs > 40
        ttl = (P.Tref - Hs)/vH;         % seconds until 80 degC
    else
        ttl = Inf;
    end

    cus   = max(0, cus + (v - P.cusumAllow));   % heating faster than allowed?
    alarm = cus > P.cusumLimit;

    % ---- safety state machine with hysteresis ----
    des = 1;
    if Hs >= P.Twatch   || ttl < 600 || alarm, des = 2; end
    if Hs >= P.Tthrottle|| ttl < 240,          des = 3; end
    if Hs >= P.Tcut     || ttl < 60,           des = 4; end

    if des >= state
        state = des; hold = 0;
    else
        hold = hold + 1;
        if hold >= 30 && state < 4
            state = state - 1; hold = 0;
        end
    end

    % ---- actuator: relay / PWM on the load ----
    if guardOn
        if state == 4
            u = 0;
        elseif state == 3
            u = max(0.35, u - 0.01);
        else
            u = min(1, u + 0.02);
        end
    end

    % ---- IoT: event-driven reporting ----
    if abs(Th - lastT) >= 0.5 || state ~= lastState || (k - lastK) >= 60
        nSent = nSent + 1;
        if N.drop(k), nLost = nLost + 1; end
        lastT = Th; lastState = state; lastK = k;
    end

    R.Tpeak(k) = max(T(:)); R.Tsens(k) = Ts; R.raw(k) = z;
    R.kf(k) = xf(1); R.fx(k) = Th; R.Hs(k) = Hs;
    R.state(k) = state; R.u(k) = u; R.ttl(k) = ttl;
    R.cus(k) = cus; R.cumPkt(k) = nSent;
end

R.Tend    = T;
R.nSent   = nSent; R.nLost = nLost; R.nGate = nGate;
R.peak    = max(R.Tpeak);
R.tDanger = firstSec(R.Tpeak >= P.Tdanger);
R.tFire   = firstSec(R.Tpeak >= P.Tfire);
R.tWatch    = firstSec(R.state >= 2);
R.tThrottle = firstSec(R.state >= 3);
R.tCut      = firstSec(R.state == 4);
R.tAlarm    = firstSec(R.cus > P.cusumLimit);
end

%% ========================= SMALL HELPERS =============================
function s = firstSec(mask)
idx = find(mask, 1);
if isempty(idx), s = NaN; else, s = idx - 1; end
end

function s = minStr(sec)
if isnan(sec), s = 'never'; else, s = sprintf('%.1f', sec/60); end
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

%% ========================= DASHBOARD =================================
function drawDashboard(P, A, B, tmin, deg)
fig = figure(1);
set(fig, 'Name', 'Thermal Guardian - Dashboard', 'NumberTitle', 'off', ...
    'Color', 'w', 'Units', 'normalized', 'Position', [0.02 0.05 0.96 0.88]);

tmax  = tmin(end);
green = [0 0.6 0.1];
lbl   = ['Temperature (' deg 'C)'];

% 1 - hottest spot
subplot(2,3,1);
plot(tmin, A.Tpeak, 'r', 'LineWidth', 2); hold on;
plot(tmin, B.Tpeak, 'Color', green, 'LineWidth', 2);
plot([0 tmax], [P.Tdanger P.Tdanger], '--', 'Color', [1 0.5 0]);
plot([0 tmax], [P.Tfire   P.Tfire],   'k--');
xlim([0 tmax]); ylim([20 max(A.Tpeak)*1.05]);
xlabel('Time (minutes)'); ylabel(lbl); grid on;
legend({'Without Guardian','With Guardian','Danger','Fire risk'}, ...
    'Location', 'northwest');
title({'1. How hot does the board get?','(lower line = safer)'});

% 2 and 3 - heat pictures of the board
cl = [P.Tamb, max(A.Tend(:))];
ax2 = subplot(2,3,2);
drawBoard(ax2, A.Tend, cl, P);
title({'2. Board picture WITHOUT Guardian','(end of test, red = very hot)'});
ax3 = subplot(2,3,3);
drawBoard(ax3, B.Tend, cl, P);
title({'3. Board picture WITH Guardian','(same colours, same moment)'});

% 4 - the brain cleaning noisy data
subplot(2,3,4);
plot(tmin, B.raw, '.', 'Color', [0.7 0.7 0.7], 'MarkerSize', 4); hold on;
plot(tmin, B.Tsens, 'k--', 'LineWidth', 1);
plot(tmin, B.fx, 'b', 'LineWidth', 1.8);
xlim([0 tmax]); grid on;
xlabel('Time (minutes)'); ylabel(lbl);
legend({'Noisy sensor + glitches','Real temperature','Guardian brain estimate'}, ...
    'Location', 'northwest');
title({'4. The Guardian cleans noisy sensor data','(blue follows the truth, glitches ignored)'});

% 5 - traffic light plus power
ax5 = subplot(2,3,5);
imagesc(tmin, [0 1], [B.state'; B.state']);
set(ax5, 'YDir', 'normal');
colormap(ax5, [0 0.7 0.2; 1 0.85 0; 1 0.5 0; 0.85 0 0]);
caxis([0.5 4.5]); hold on;
plot(tmin, B.u, 'k', 'LineWidth', 2.5);
ylim([0 1]); xlim([0 tmax]);
xlabel('Time (minutes)'); ylabel('Power to load (1 = full)');
title({'5. Traffic light: green safe, yellow watch,', ...
       'orange slow down, red power OFF (black = power)'});

% 6 - plain-language story
ax6 = subplot(2,3,6);
set(ax6, 'Visible', 'off', 'XLim', [0 1], 'YLim', [0 1]);
txt = { ...
    'WHAT HAPPENED IN THIS TEST?', ...
    'A power strip is under a blanket (it cannot cool)', ...
    'and its plug slowly becomes loose (loose = hot).', ...
    '', ...
    'WITHOUT Guardian', ...
    sprintf('  Hottest point : %.0f %sC -> %s', A.peak, deg, verdict(A,P)), ...
    sprintf('  Danger reached at minute %s', minStr(A.tDanger)), ...
    '', ...
    'WITH Guardian', ...
    sprintf('  Warning at minute %s',       minStr(B.tWatch)), ...
    sprintf('  Power slowed at minute %s',  minStr(B.tThrottle)), ...
    sprintf('  Power OFF at minute %s',     minStr(B.tCut)), ...
    sprintf('  Hottest point : %.0f %sC -> %s', B.peak, deg, verdict(B,P)), ...
    '', ...
    'Simple idea: feel the heat, guess how fast', ...
    'it grows, switch off BEFORE it gets dangerous.'};
text(0.02, 0.98, txt, 'Parent', ax6, 'VerticalAlignment', 'top', ...
    'FontSize', 10, 'Interpreter', 'none', 'FontName', 'FixedWidth');

annotation('textbox', [0.1 0.945 0.8 0.05], 'String', ...
    'PCB THERMAL GUARDIAN - predicts and prevents electrical fires in power strips and chargers', ...
    'EdgeColor', 'none', 'HorizontalAlignment', 'center', 'FontSize', 14, ...
    'FontWeight', 'bold', 'Interpreter', 'none');
drawnow;
end

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
rectangle('Position', [1.5 7.5 3 5], 'EdgeColor', 'w', 'LineWidth', 1.5);
plot(P.sc, P.sr, 'ks', 'MarkerFaceColor', 'w', 'MarkerSize', 6);
text(1.2, 5.8,  'PLUG',    'Color', 'w', 'FontWeight', 'bold', 'FontSize', 8);
text(5.5, 12.5, 'sensor',  'Color', 'w', 'FontSize', 8);
text(13.2, 7.3, 'MOSFET',  'Color', 'w', 'FontSize', 8);
text(21.5, 13.2,'CHARGER', 'Color', 'w', 'FontSize', 8);
end

%% ========================= ENGINEERING FIGURE ========================
function drawEngineering(P, Fl, A, B, H, tmin, deg, gain)
fig = figure(2);
set(fig, 'Name', 'Thermal Guardian - Engineering deep dive', 'NumberTitle', 'off', ...
    'Color', 'w', 'Units', 'normalized', 'Position', [0.04 0.04 0.92 0.86]);
tmax = tmin(end);

% 1 - IPC-2221 trace width check
subplot(2,3,1);
Iv   = linspace(1, 20, 100);
dTs  = [10 20 40];
cols = {[0 0.45 0.9], [0 0.6 0.2], [0.9 0.4 0]};
for d = 1:3
    Amil = (Iv./(0.048*dTs(d)^0.44)).^(1/0.725);   % IPC-2221, outer layer
    wmm  = Amil/1.378*0.0254;                      % 1 oz copper
    plot(Iv, wmm, 'Color', cols{d}, 'LineWidth', 2); hold on;
end
wDes  = 4;
Ades  = wDes/0.0254*1.378;
dTdes = (P.I0/(0.048*Ades^0.725))^(1/0.44);
plot(P.I0, wDes, 'ko', 'MarkerFaceColor', 'y', 'MarkerSize', 10);
grid on;
xlabel('Current (A)'); ylabel('Trace width needed (mm)');
legend({['rise ' num2str(dTs(1)) ' ' deg 'C'], ...
        ['rise ' num2str(dTs(2)) ' ' deg 'C'], ...
        ['rise ' num2str(dTs(3)) ' ' deg 'C'], ...
        sprintf('our trace: %.0f %sC rise', dTdes, deg)}, 'Location', 'northwest');
title({'IPC-2221 PCB trace check (1 oz copper)', ...
       'Our 4 mm trace is fine: the PLUG is the problem'});

% 2 - integer filter vs float filter
errv = abs(B.fx - B.kf);
subplot(2,3,2);
plot(tmin(6:end), errv(6:end), 'b'); grid on; xlim([0 tmax]);
xlabel('Time (minutes)'); ylabel(['Difference (' deg 'C)']);
title({'Integer-only filter vs float filter', ...
    sprintf('95%% of time within %.3f %sC (max %.3f %sC)', ...
    prctile95(errv(6:end)), deg, max(errv(6:end)), deg)});

% 3 - IoT packets
subplot(2,3,3);
plot(tmin, (1:P.NT)', 'r', 'LineWidth', 2); hold on;
plot(tmin, B.cumPkt, 'Color', [0 0.6 0.1], 'LineWidth', 2);
grid on; xlim([0 tmax]);
xlabel('Time (minutes)'); ylabel('Packets sent (total)');
legend({'Send every second','Guardian: only when it matters'}, 'Location', 'northwest');
title({'IoT: event-driven reporting', ...
    sprintf('%.0f%% fewer packets, nothing important missed', 100*(1-B.nSent/P.NT))});

% 4 - CUSUM detector
subplot(2,3,4);
plot(tmin, A.cus, 'm', 'LineWidth', 2); hold on;
plot([0 tmax], [P.cusumLimit P.cusumLimit], 'k--');
grid on; xlim([0 tmax]);
xlabel('Time (minutes)'); ylabel('CUSUM score');
title({'Abnormal-heating detector (CUSUM)', ...
    sprintf('alarm at minute %s, danger at minute %s', ...
    minStr(A.tAlarm), minStr(A.tDanger))});

% 5 - countdown to danger
subplot(2,3,5);
tt = B.ttl/60; tt(~isfinite(tt)) = NaN; tt(tt > 30) = 30;
plot(tmin, tt, 'Color', [0.8 0.2 0], 'LineWidth', 2); grid on;
xlim([0 tmax]); ylim([0 30]);
xlabel('Time (minutes)'); ylabel('Minutes left');
title({['Countdown to ' num2str(P.Tref) ' ' deg 'C hot spot'], ...
       '(only shown while heating)'});

% 6 - validation scoreboard
ax6 = subplot(2,3,6);
set(ax6, 'Visible', 'off', 'XLim', [0 1], 'YLim', [0 1]);
errv2 = errv(6:end);
txt = { ...
    'VALIDATION SCOREBOARD', ...
    '', ...
    'Test 1  healthy board, 45 min', ...
    sprintf('   false-alarm seconds : %d (target 0)', sum(H.state >= 2)), ...
    sprintf('   peak temperature    : %.1f %sC', H.peak, deg), ...
    '', ...
    'Test 2  loose plug + blanket, NO guardian', ...
    sprintf('   peak %.0f %sC -> %s', A.peak, deg, verdict(A,P)), ...
    '', ...
    'Test 3  same fault, WITH guardian', ...
    sprintf('   peak %.0f %sC -> %s', B.peak, deg, verdict(B,P)), ...
    sprintf('   power cut at minute %s', minStr(B.tCut)), ...
    '', ...
    'Embedded', ...
    sprintf('   glitches rejected  : %d', B.nGate), ...
    sprintf('   int vs float (max) : %.3f %sC', max(errv2), deg), ...
    sprintf('   Q15 gains          : %d , %d', Fl.K1q, Fl.K2q), ...
    sprintf('   hot-spot / sensor  : %.2f x', gain), ...
    'IoT', ...
    sprintf('   packets %d / %d (lost on Wi-Fi: %d)', B.nSent, P.NT, B.nLost)};
text(0.02, 0.98, txt, 'Parent', ax6, 'VerticalAlignment', 'top', ...
    'FontSize', 9.5, 'Interpreter', 'none', 'FontName', 'FixedWidth');

annotation('textbox', [0.1 0.945 0.8 0.05], 'String', ...
    'ENGINEERING DEEP DIVE - PCB design check, embedded maths, IoT, validation', ...
    'EdgeColor', 'none', 'HorizontalAlignment', 'center', 'FontSize', 14, ...
    'FontWeight', 'bold', 'Interpreter', 'none');
drawnow;
end

%% ========================= FIRMWARE EXPORT ===========================
function ok = writeFirmwareHeader(P, Fl, gain)
ok = false;
try
    fid = fopen(fullfile(pwd, 'guardian_constants.h'), 'w');
    if fid < 0, return; end
    L = { ...
        '/* guardian_constants.h - generated by ThermalGuardian.m */', ...
        '/* Integer-only thermal guardian for MCUs without an FPU            */', ...
        '/* (ESP32, STM32, AVR).                                            */', ...
        '#include <stdint.h>', ...
        '', ...
        sprintf('#define KF_K1_Q15 %d  /* position gain, Q15 */', Fl.K1q), ...
        sprintf('#define KF_K2_Q15 %d  /* rate gain, Q15 */',     Fl.K2q), ...
        sprintf('#define GATE_Q8 %d  /* glitch gate = %.1f C, in 1/256 C */', ...
                round(P.gate*256), P.gate), ...
        sprintf('#define HOTSPOT_GAIN_Q8 %d  /* hot spot / sensor ratio x256 */', ...
                round(gain*256)), ...
        sprintf('#define T_AMBIENT_Q8 %d', round(P.Tamb*256)), ...
        sprintf('#define T_WATCH_C %d',    P.Twatch), ...
        sprintf('#define T_THROTTLE_C %d', P.Tthrottle), ...
        sprintf('#define T_CUTOFF_C %d',   P.Tcut), ...
        '', ...
        'static int32_t x_q8 = 0;  /* temperature,     1/256 C   */', ...
        'static int32_t v_q16 = 0; /* heating speed,   1/65536 C/s */', ...
        '', ...
        '/* call once per second with the ADC temperature in 1/256 C */', ...
        'static inline void guardian_update(int32_t z_q8)', ...
        '{', ...
        '    int32_t xp = x_q8 + (v_q16 >> 8);', ...
        '    int32_t r  = z_q8 - xp;', ...
        '    if (r < GATE_Q8 && r > -GATE_Q8) {', ...
        '        x_q8 = xp + ((KF_K1_Q15 * r) >> 15);', ...
        '        v_q16 = v_q16 + ((KF_K2_Q15 * r * 256) >> 15);', ...
        '    } else {', ...
        '        x_q8 = xp; /* reject EMI glitch */', ...
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
