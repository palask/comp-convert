# --- OPTIONS: START ---

# Define the input and output folders
$inFolder = "in"
$outFolder = "out"

# Define the quality for videos
# The range of the CRF scale is 0–51, where 0 is lossless, 23 is the default, and 51 is worst quality possible. A lower value generally leads to higher quality, and a subjectively sane range is 17–28. Consider 17 or 18 to be visually lossless or nearly so.
$videoQualityCrf = 23

# Define the encoding speed for videos
# Possible values: ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow
$videoEncodingSpeed = "medium"

# Define the quality for images
$imageQuality = 90

# Define the list of video extensions
$vidExtensions = @(".mp4", ".mkv", ".mov", ".webm", ".m4v")

# Define the list of image extensions
$imgExtensions = @(".png", ".jpg", ".jpeg", ".bmp", ".webp")

# --- OPTIONS: END ---

Write-Output "CompConvert: Starting..."

# Create the output folder if it doesn't exist
if (!(Test-Path $outFolder)) {
    New-Item -ItemType Directory -Path $outFolder
    Write-Host "[Create folder] $($outFolder)" -ForegroundColor Blue
}

# Resolve the absolute paths based on the current directory
$inFolderAbsolute = Join-Path -Path (Get-Location) -ChildPath $inFolder
$outFolderAbsolute = Join-Path -Path (Get-Location) -ChildPath $outFolder

# Get all subfolders recursively
$subfolders = Get-ChildItem -Path $inFolderAbsolute -Directory -Recurse

function Get-ProgramPath {
    param (
        [Parameter(Mandatory)]
        [string]$ProgramName
    )

    $programExe = "$ProgramName.exe"
    $currentDirPath = Join-Path -Path (Get-Location) -ChildPath $programExe
    $pathName = $ProgramName

    if (Test-Path $currentDirPath) {
        Write-Host "$ProgramName found in script directory"
        return $currentDirPath
    }
    elseif (Get-Command $pathName -ErrorAction SilentlyContinue) {
        Write-Host "$ProgramName found in system PATH"
        return $pathName
    }
    else {
        Write-Host "$ProgramName was not found"
        return ""
    }
}

# Check the locations of ffmpeg, ffprobe, and magick
$ffmpegPath = Get-ProgramPath -ProgramName "ffmpeg"
$ffprobePath = Get-ProgramPath -ProgramName "ffprobe"
$magickPath = Get-ProgramPath -ProgramName "magick"

# Iterate through each subfolder and create the same structure inside the destination folder
$subfolders | ForEach-Object {
    # Get the relative path of the subfolder within the inFolder
    $relativePath = $_.FullName.Substring($inFolderAbsolute.Length).TrimStart('\')

    # Combine the destination folder path with the relative path to get the new folder path
    $newFolderPath = Join-Path -Path $outFolderAbsolute -ChildPath $relativePath
    
    # Create the directory if it doesn't already exist
    if (-not (Test-Path -Path $newFolderPath)) {
        New-Item -ItemType Directory -Path $newFolderPath | Out-Null
        Write-Host "[Create folder] $($newFolderPath)" -ForegroundColor Blue
    }
}

Write-Output "Created the folder structure if required"

$files = Get-ChildItem -Path $inFolder -File -Recurse

$videoFiles = $files | Where-Object { $vidExtensions -contains $_.Extension.ToLower() }

# Make sure ffmpeg is installed if required
if ($videoFiles | Select-Object -First 1 -And $ffmpegPath -eq "") {
    Write-Error "There are video files inside the input folder, but ffmpeg is not installed"
    exit 1
}

# Make sure ffprobe is installed if required
if ($videoFiles | Select-Object -First 1 -And $ffprobePath -eq "") {
    Write-Error "There are video files inside the input folder, but ffprobe is not installed"
    exit 1
}

# Iterate over each video file in the input folder
$videoFiles | ForEach-Object {
    $inputFile = $_.FullName
    $baseName = $_.BaseName
    $relativePath = $_.FullName.Substring($inFolderAbsolute.Length).TrimStart('\')
    $outputFolder = Join-Path $outFolder (Split-Path $relativePath -Parent)
    $outputFile = Join-Path $outputFolder "$baseName.mp4"

    # Check if the output file exists, and if it does, append a number to the filename
    $counter = 1
    while (Test-Path "$outputFile") {
        $outputFile = Join-Path $outputFolder "$baseName-$counter.mp4"
        $counter++
    }

    # Use ffprobe to get the audio bitrate from the video
    $ffprobeAudioArgs = @(
        "-v", "error",
        "-select_streams", "a:0",
        "-show_entries", "stream=bit_rate",
        "-of", "default=noprint_wrappers=1:nokey=1",
        "`"$inputFile`""
    )
    $audioBitrateRaw = & "$ffprobePath" $ffprobeAudioArgs
    $audioBitrateRaw = if ($audioBitrateRaw) { $audioBitrateRaw.Trim() } else { "" }

    # Handle non-numeric bitrate (e.g., "N/A" or empty)
    [int]$parsedAudioBitrate = 0
    if ([int]::TryParse($audioBitrateRaw, [ref]$parsedAudioBitrate)) {
        # Set audio bitrate based on the current bitrate
        $audioBitrateSetting = if ($parsedAudioBitrate -ge 192000) { "192k" } else { "128k" }
    } else {
        # Default/fallback if no audio or invalid value
        $audioBitrateSetting = "128k"
    }

    # Use ffprobe to get the video height
    $ffprobeVideoArgs = @(
        "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=height",
        "-of", "default=noprint_wrappers=1:nokey=1",
        "`"$inputFile`""
    )
    $videoHeight = & "$ffprobePath" $ffprobeVideoArgs
    $videoHeight = [int]$videoHeight

    # Run the ffmpeg command to convert the video to the calculated dimensions
    $ffmpegArgs = @(
        "-i", "`"$inputFile`"",
        "-c:v", "libx264",
        "-preset", "$videoEncodingSpeed",
        "-crf", "$videoQualityCrf",
        "-pix_fmt", "yuv420p",
        "-c:a", "libfdk_aac",
        "-b:a", "$audioBitrateSetting"
    )
    # Add the scaling filter if the height is 1440 or higher
    if ($videoHeight -ge 1440) {
        $scaleFilter = "-vf", "scale=-2:1080"  # Scale the height to 1080p, maintaining aspect ratio
        $ffmpegArgs += $scaleFilter
    }

    # Specify the output file
    $ffmpegArgs += "`"$outputFile`""

    Write-Host "[ffmpeg] $($inputFile)" -ForegroundColor Blue
    Start-Process -NoNewWindow -FilePath $ffmpegPath -ArgumentList $ffmpegArgs -Wait -PassThru
}

$imageFiles = $files | Where-Object { $imgExtensions -contains $_.Extension.ToLower() }

# Make sure magick is installed if required
if ($videoFiles | Select-Object -First 1 -And $magickPath -eq "") {
    Write-Error "There are image files inside the input folder, but ImageMagick is not installed"
    exit 1
}

# Iterate over each image file in the input folder
$imageFiles | ForEach-Object {
    $inputFile = $_.FullName
    $baseName = $_.BaseName
    $relativePath = $_.FullName.Substring($inFolderAbsolute.Length).TrimStart('\')
    $outputFolder = Join-Path $outFolder (Split-Path $relativePath -Parent)
    $outputFile = Join-Path $outputFolder "$baseName.jpg"

    # Check if the output file exists, and if it does, append a number to the filename
    $counter = 1
    while (Test-Path "$outputFile") {
        $outputFile = Join-Path $outputFolder "$baseName-$counter.jpg"
        $counter++
    }

    # Run the ImageMagick command to resize the image
    $magickArgs = "`"$inputFile`" -quality $imageQuality `"$outputFile`""

    Write-Host "[ImageMagick] $($inputFile)" -ForegroundColor Blue
    Start-Process -NoNewWindow -FilePath $magickPath -ArgumentList $magickArgs -Wait -PassThru
}

Write-Output "CompConvert: Finished"
