function power = goertzel_power(samples, fs, freq)
    N = length(samples);
    k = round(0.5 + (N * freq / fs));
    omega = (2*pi*k) / N;
    coeff = 2*cos(omega);

    s_prev = 0;
    s_prev2 = 0;

    for n = 1:N
        s = samples(n) + coeff * s_prev - s_prev2;
        s_prev2 = s_prev;
        s_prev = s;
    end

    power = s_prev2^2 + s_prev^2 - coeff * s_prev * s_prev2;
end
