% Function to process WAV files according to the user's desired roomType and recCond
function processWavFiles(roomType, recCond, fs, recTimeDelay, recFsDeviation)

    % Set directory and sound source
    dirName = "./impulse_dataset/";
    srcName = ["target", "int1", "int2", "int3"];

    % Number of sound sources
    nSrc = str2double(extractBefore(recCond, 2)) + 1; % extract

    % List of recording channels
    if     nSrc == 3 % case of either 2A. 2B, or 2C
        listCh = [1:4, 9:12];
    elseif nSrc == 4 % case of either 3A, or 3B
        listCh = 1:12;
    else
        error("The input argument 'recCond' is incorrect.\n");
    end

    % Create 2D string array for input filepath
    inFilePath = strings(nSrc, length(listCh));

    % Create file paths
    for iSrc = 1:nSrc
        for iCh = 1:length(listCh)
            inFilePath(iSrc, iCh) = dirName + roomType + "_" + recCond + "_" + srcName(iSrc) + "_ir_" + listCh(iCh) + ".wav";
        end
    end

    % Create 2D array for output filepath
    outFilePath = strings(nSrc, length(listCh));

    % Generate output file paths and call resampleCorrectWav for each sound source
    for iSrc = 1:nSrc
        inCurrentFiles = inFilePath(iSrc, :);
        outFilePath(iSrc, :) = genOutFilePath(roomType, recCond, srcName(iSrc), fs, recTimeDelay, recFsDeviation);
        outCurrentFiles = outFilePath(iSrc, :);
        resampleCorrectWav(inCurrentFiles, outCurrentFiles, fs, recTimeDelay, recFsDeviation); 
    end
end

% Function to apply desired fs, recTimeDelay, and recFsDeviation
function resampleCorrectWav(inputFiles, outputFiles, inputFs, recTimeDelay, recFsDeviation)

    % Set default sample rate
    defaultFs = 96000; % [Hz]

    % Set sample rate
    if inputFs > 0 && inputFs <= defaultFs
        fs = inputFs;
        disp(['Specified sample rate: fs = ', num2str(fs), ' Hz']);
    else
        error('Invalid sample rate. Fs must be greater than 0 Hz and less than 96 kHz.');
    end

    % Number of samples
    audioData = audioread(inputFiles{1});
    numSamples = length(audioData);

    % Number of input files
    numFiles = length(inputFiles);
    
    % Initialize 2D array to store resampled data
    resampledData = zeros(numFiles, numSamples);

    % Process each input file
    for i = 1:numFiles
        inputFile = inputFiles{i};

        % Loading WAV files
        [currentAudioData, originalFs] = audioread(inputFile);
    
        % Check whether resample is required
        if fs ~= originalFs
            p = fs;         % New sample rate
            q = originalFs; % Original sample rate
            n = 100;        % Length of the FIR filter

            % Resample with specified filter length
            resampledAudioData = resample(currentAudioData, p, q, n);
            currentNumSamples = length(resampledAudioData);
            resampledData(i, 1:currentNumSamples) = resampledAudioData;

            disp(['Audio data was resampled from ', num2str(originalFs), ' Hz to ', num2str(fs), ' Hz.']);
        else
            resampledData(i, :) = audioData;
            disp('No resampling was required.');
        end
    end

    % Apply recTimeDelay
    timeProcessedData = applyRecTimeDelay(resampledData, fs, recTimeDelay);

    % Apply recFsDeviation
    applyRecFsdeviation(timeProcessedData, fs, recFsDeviation, outputFiles);

end

% Function to generate delay of recording time
function audioDataDelayed = applyRecTimeDelay(audioData, fs, recTimeDelay)

    % Check if recTimeDelay contains negative values
    if any(recTimeDelay < 0)
        error('recTimeDelay contains negative values. All elements must be non-negative.');
    end

    % Transpose audioData
    tAudioData = audioData.';

    % Convert recTimeDelay units from [s] to [samples]
    delaySamples = round(recTimeDelay * fs); % integer value

    % Identification of the number of channels
    numChannels = size(audioData, 1);

    % Identification of the number of mic array
    if numChannels == 8      % 2 mic arrays
        groups = [1:4; 5:8];
    elseif numChannels == 12 % 3 mic arrays
        groups = [1:4; 5:8; 9:12];
    else
        error('The number of unsupported channels.');
    end

    % Check the number of mic arrays and elements in recTimeDelay
    if length(recTimeDelay) ~= size(groups, 1)
        error('The number of mic arrays dose not match the number of elements in recTimeDelay.');
    end

    % Calcurate max delay samples
    maxDelay = max(recTimeDelay);
    maxDelaySamples = round(maxDelay * fs);

    % Apply delay of recording time
    numSamples = size(audioData, 2);
    audioDataDelayed = zeros(numSamples + maxDelaySamples, numChannels); % Initialization
    for g = 1:size(groups, 1)
        groupChannels = groups(g, :);
        delay = delaySamples(g);

        if delay > 0
            % Fill in 0 for the displacement part
            delayedData = [zeros(delay, length(groupChannels)); tAudioData(:, groupChannels)];
            
            % Store the delayed data in the appropriate section
            audioDataDelayed(1:length(delayedData), groupChannels) = delayedData;
        else
            audioDataDelayed(1:length(tAudioData), groupChannels) = tAudioData(:, groupChannels);
        end
    end
end

% Function to apply sample rate deviation
function applyRecFsdeviation(audioData, fs, recFsDeviation, inputFiles)

    % Check if recFsDeviation contains negative values
    if any(recFsDeviation < 0)
        error('recFsDeviation contains negative values. All elements must be non-negative.');
    end

    % comvert ppm value to sample rate
    newFs = fs * (1 + recFsDeviation * 10^-6);

    % Identification of the number of channels
    numChannels = size(audioData, 2);

    % Identification of the number of mic array
    if numChannels == 8      % 2 mic arrays
        groups = [1:4; 5:8];
    elseif numChannels == 12 % 3 mic arrays
        groups = [1:4; 5:8; 9:12];
    else
        error('The number of unsupported channels.');
    end

    % Check the number of mic arrays and elements in recFsDeviaiton
    if length(recFsDeviation) ~= size(groups, 1)
        error('The number of mic arrays dose not match the number of elements in recFsDeviation.');
    end

    % Calcurate max samples after resampling
    maxPpm = max(recFsDeviation);
    maxNewFs = fs * (1 + maxPpm * 10^-6);
    maxNumSamples = ceil(size(audioData, 1) * (maxNewFs / fs));

    % Initialize with extended size
    audioDataAdjusted = zeros(maxNumSamples, numChannels);

    % Apply sample rate deviation
    for i = 1:size(groups, 1)
        groupChannels = groups(i, :);

        disp(['newFs = ', num2str(newFs(i))]);

        % Create original time vector
        tOriginal = (0:length(audioData(:, groupChannels)) - 1) / fs;

        % Create a time vector based on the new sample rate
        tNew = 0:1/newFs(i):(length(audioData(:, groupChannels)) - 1) / fs;

        % Create griddedInterpolant object
        F = griddedInterpolant(tOriginal, audioData(:, groupChannels), 'spline');

        % Perform resampling based on new time vector
        resampledData = F(tNew);

        % Apply resampled data
        audioDataAdjusted(1:length(resampledData), groupChannels) = resampledData;
    end

    % Output resampled data as a WAV file
    for j = 1:size(groups, 1)
        for k = 1:length(inputFiles)
            audiowrite(inputFiles(k), audioDataAdjusted(:, k), fs);
        end
    end
end

% Function to generate output path
function outputFiles = genOutFilePath(roomType, recCond, soundSrc, fs, recTimeDelay, recFsDeviation)

    % Create output derectory
    outputDir = "./output/";
    if ~exist(outputDir, 'dir')
        mkdir(outputDir);
    end

    % Number of sound sources
    nSrc = str2double(extractBefore(recCond, 2)) + 1; % extract

    % List of recording channels
    if     nSrc == 3 % case of either 2A. 2B, or 2C
        listCh = [1:4, 9:12];
    elseif nSrc == 4 % case of either 3A, or 3B
        listCh = 1:12;
    else
        error("The input argument 'recCond' is incorrect.\n");
    end

    % Create array for output file path
    outputFiles = strings(1, length(listCh));

    % Generate output file path
    if nSrc == 3
        for iCh = 1:length(listCh)
            outputFiles(iCh) = outputDir + roomType + "_" + recCond + "_" + soundSrc + "_fs" + fs + "_td" + sprintf("%5.3f", recTimeDelay(1)) + "-" + sprintf("%5.3f", recTimeDelay(2)) + "_fd" + sprintf("%5.3f", recFsDeviation(1)) + "-" + sprintf("%5.3f", recFsDeviation(2)) + "_" + listCh(iCh) + ".wav";
        end
    elseif nSrc == 4
        for iCh = 1:length(listCh)
            outputFiles(iCh) = outputDir + roomType + "_" + recCond + "_" + soundSrc + "_fs" + fs + "_td" + sprintf("%5.3f", recTimeDelay(1)) + "-" + sprintf("%5.3f", recTimeDelay(2)) + "-" + sprintf("%5.3f", recTimeDelay(3)) + "_fd" + sprintf("%5.3f", recFsDeviation(1)) + "-" + sprintf("%5.3f", recFsDeviation(2)) + "-" + sprintf("%5.3f", recFsDeviation(3)) + "_" + listCh(iCh) + ".wav";
        end
    end
end
