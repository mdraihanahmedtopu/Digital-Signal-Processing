%% DTMF detection from MICROPHONE (improved)
clear; clc; close all;

%% Common settings
fs    = 8000;   % sample rate (8 kHz is enough for DTMF)
nbits = 16;
nch   = 1;

% DTMF frequencies
low_freqs  = [697 770 852 941];
high_freqs = [1209 1336 1477 1633];

% DTMF lookup table
dtmf_map = containers.Map;
dtmf_map('697_1209') = '1'; dtmf_map('697_1336') = '2'; dtmf_map('697_1477') = '3';
dtmf_map('770_1209') = '4'; dtmf_map('770_1336') = '5'; dtmf_map('770_1477') = '6';
dtmf_map('852_1209') = '7'; dtmf_map('852_1336') = '8'; dtmf_map('852_1477') = '9';
dtmf_map('941_1209') = '*'; dtmf_map('941_1336') = '0'; dtmf_map('941_1477') = '#';
dtmf_map('697_1633') = 'A'; dtmf_map('770_1633') = 'B';
dtmf_map('852_1633') = 'C'; dtmf_map('941_1633') = 'D';

%% =========================================================
%  PART 1 : LONG RECORDING (for 11–12 digits)
% ==========================================================
recTime = 12;    % seconds – good for 11–12 key presses

recObj = audiorecorder(fs, nbits, nch);

disp('>>> PART 1: Speak / play 11–12 DTMF digits now (12 s total)...');
recordblocking(recObj, recTime);
disp('>>> Recording finished.');

audio = getaudiodata(recObj);
audio = audio(:);

% Normalize whole recording to avoid amplitude issues
if max(abs(audio)) > 0
    audio = audio / max(abs(audio));
end

% ----- Short-time energy segmentation -----
frame_len = round(0.025 * fs);   % 25 ms
hop       = round(0.010 * fs);   % 10 ms

num_frames = floor((length(audio) - frame_len) / hop) + 1;
E = zeros(num_frames, 1);

for k = 1:num_frames
    idx = (k-1)*hop + 1;
    frame = audio(idx : idx+frame_len-1);
    E(k) = sum(frame.^2);
end

thr  = 0.05 * max(E);         % more sensitive
mask = (E > thr);
mask = movmean(double(mask), 5) > 0.5;

mask_samples = false(size(audio));
for k = 1:num_frames
    if mask(k)
        idx  = (k-1)*hop + 1;
        idx2 = min(idx + frame_len - 1, length(audio));
        mask_samples(idx:idx2) = true;
    end
end

d      = diff([0; mask_samples; 0]);
starts = find(d == 1);
ends   = find(d == -1) - 1;

detected_keys_offline = '';
last_f_low  = NaN;
last_f_high = NaN;

for s = 1:length(starts)

    seg_start = starts(s);
    seg_end   = ends(s);
    seg_dur   = (seg_end - seg_start + 1) / fs;

    % ignore tiny clicks
    if seg_dur < 0.030
        continue;
    end

    segment = audio(seg_start:seg_end);

    % normalize segment
    if max(abs(segment)) > 0
        segment = segment / max(abs(segment));
    end

    low_power  = zeros(1, length(low_freqs));
    high_power = zeros(1, length(high_freqs));

    for i = 1:length(low_freqs)
        low_power(i) = goertzel_power(segment, fs, low_freqs(i));
    end
    for i = 1:length(high_freqs)
        high_power(i) = goertzel_power(segment, fs, high_freqs(i));
    end

    [maxLow, li]  = max(low_power);
    [maxHigh, hi] = max(high_power);

    % ---- extra check: strongest must dominate group ----
    if maxLow <= 0 || maxHigh <= 0
        continue;
    end
    if maxLow  < 0.4*sum(low_power) || maxHigh < 0.4*sum(high_power)
        % looks like noise, skip
        continue;
    end

    f_low  = low_freqs(li);
    f_high = high_freqs(hi);

    key_pair = sprintf('%d_%d', f_low, f_high);
    if isKey(dtmf_map, key_pair)
        detected_keys_offline = [detected_keys_offline dtmf_map(key_pair)];
        last_f_low  = f_low;
        last_f_high = f_high;
    end
end

disp('==========================================');
disp('OFFLINE (12 s) RESULT:');
if isempty(detected_keys_offline)
    disp('  No valid DTMF key detected.');
else
    fprintf('  Detected Key Sequence: %s\n', detected_keys_offline);
    fprintf('  Last Low  Freq : %.0f Hz\n', last_f_low);
    fprintf('  Last High Freq : %.0f Hz\n', last_f_high);
end
disp('==========================================');


%% =========================================================
%  PART 2 : REALTIME STYLE (chunk-by-chunk in a loop)
% ==========================================================
disp('>>> PART 2: REALTIME MODE');
disp('    Press CTRL+C in the command window to stop.');

chunkTime = 0.15;               % 150 ms chunk – better for key presses
chunkObj  = audiorecorder(fs, nbits, nch);

detected_keys_rt = '';
lastKey = '';                   % to avoid repeats while holding a key

while true
    % record a short chunk
    recordblocking(chunkObj, chunkTime);
    x = getaudiodata(chunkObj);
    x = x(:);

    % skip almost-silence
    if max(abs(x)) < 0.03
        lastKey = '';   % reset so next valid key is accepted
        continue;
    end

    % normalize chunk
    if max(abs(x)) > 0
        x = x / max(abs(x));
    end

    % compute Goertzel powers on the WHOLE chunk
    low_power  = zeros(1, length(low_freqs));
    high_power = zeros(1, length(high_freqs));

    for i = 1:length(low_freqs)
        low_power(i) = goertzel_power(x, fs, low_freqs(i));
    end
    for i = 1:length(high_freqs)
        high_power(i) = goertzel_power(x, fs, high_freqs(i));
    end

    [maxLow, li]  = max(low_power);
    [maxHigh, hi] = max(high_power);

    % ---- extra dominance check ----
    if maxLow <= 0 || maxHigh <= 0
        lastKey = '';
        continue;
    end
    if maxLow  < 0.4*sum(low_power) || maxHigh < 0.4*sum(high_power)
        % not a clear DTMF tone
        lastKey = '';
        continue;
    end

    f_low  = low_freqs(li);
    f_high = high_freqs(hi);

    key_pair = sprintf('%d_%d', f_low, f_high);

    if isKey(dtmf_map, key_pair)
        key = dtmf_map(key_pair);

        % only add/print when it changes (avoid duplicates)
        if ~strcmp(key, lastKey)
            detected_keys_rt = [detected_keys_rt key];
            lastKey = key;
            fprintf('Realtime detected: %s   (Full so far: %s)\n', key, detected_keys_rt);
        end
    else
        lastKey = '';
    end
end


%% ------------------------------------------
% Goertzel power function
%% ------------------------------------------
function P = goertzel_power(x, fs, target_f)
    N = length(x);
    if N < 5
        P = 0;
        return;
    end

    k     = round(N * target_f / fs);
    omega = 2*pi*k/N;
    coeff = 2*cos(omega);
    s_prev  = 0;
    s_prev2 = 0;

    for n = 1:N
        s       = x(n) + coeff*s_prev - s_prev2;
        s_prev2 = s_prev;
        s_prev  = s;
    end

    real_part = s_prev  - s_prev2*cos(omega);
    imag_part = s_prev2*sin(omega);

    P = real_part^2 + imag_part^2;
end
