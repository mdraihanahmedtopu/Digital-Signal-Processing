clear; clc;

% Load audio file
[audio, fs] = audioread('0.mp3');

% Convert stereo → mono
if size(audio, 2) == 2
    audio = mean(audio, 2);
end
audio = audio(:);

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

% ------------------------------------------
% STEP 1 : Short-Time Energy for segmentation
% ------------------------------------------

frame_len = round(0.025 * fs);   % 25 ms window
hop       = round(0.010 * fs);   % 10 ms hop

num_frames = floor((length(audio) - frame_len) / hop) + 1;
E = zeros(num_frames, 1);

for k = 1:num_frames
    idx = (k-1)*hop + 1;
    frame = audio(idx : idx+frame_len-1);
    E(k) = sum(frame.^2);
end

% Threshold for voice activity
thr = 0.1 * max(E);
mask = (E > thr);

% Smooth the mask
mask = movmean(double(mask), 5) > 0.5;

% Convert frame mask → sample mask
mask_samples = false(size(audio));
for k = 1:num_frames
    if mask(k)
        idx = (k-1)*hop + 1;
        idx2 = min(idx + frame_len - 1, length(audio));
        mask_samples(idx:idx2) = true;
    end
end

% Find active segments
d = diff([0; mask_samples; 0]);
starts = find(d == 1);
ends   = find(d == -1) - 1;

detected_keys = '';

% ------------------------------------------
% STEP 2 : Analyze each segment
% ------------------------------------------
for s = 1:length(starts)

    seg_start = starts(s);
    seg_end   = ends(s);
    seg_dur = (seg_end - seg_start + 1) / fs;

    % FIX: Ignore click segments < 30 ms
    if seg_dur < 0.030
        continue;
    end

    segment = audio(seg_start:seg_end);

    % --- Goertzel power computation ---
    low_power = zeros(1, length(low_freqs));
    high_power = zeros(1, length(high_freqs));

    for i = 1:length(low_freqs)
        low_power(i) = goertzel_power(segment, fs, low_freqs(i));
    end
    for i = 1:length(high_freqs)
        high_power(i) = goertzel_power(segment, fs, high_freqs(i));
    end

    % Pick strongest low + high components
    [~, li] = max(low_power);
    [~, hi] = max(high_power);

    f_low  = low_freqs(li);
    f_high = high_freqs(hi);

    key_pair = sprintf('%d_%d', f_low, f_high);

    if isKey(dtmf_map, key_pair)
        detected_keys = [detected_keys dtmf_map(key_pair)];
    end
end

disp(['Detected Key Sequence: ' detected_keys]);
disp(['Low Frequency: ' num2str(f_low) ' Hz']); 
disp(['High Frequency: ' num2str(f_high) ' Hz']);


% ------------------------------------------
% Goertzel function
% ------------------------------------------
function P = goertzel_power(x, fs, target_f)
    N = length(x);
    if N < 5
        P = 0; 
        return;
    end

    k = round(N * target_f / fs);
    omega = 2*pi*k/N;
    coeff = 2*cos(omega);
    s_prev = 0;
    s_prev2 = 0;

    for n = 1:N
        s = x(n) + coeff*s_prev - s_prev2;
        s_prev2 = s_prev;
        s_prev = s;
    end

    real_part = s_prev - s_prev2*cos(omega);
    imag_part = s_prev2*sin(omega);

    P = real_part^2 + imag_part^2;
end
