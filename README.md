# CompConvert

A PowerShell script to convert image and video files with a good compromise between quality, file size and compatibility with many devices and applications.
The folder structure of the input files is recreated for the converted output.

## Requirements

Operating System: Windows only

The following programs need to be available in the PATH or inside the folder of this file:

- To convert video files:
	- *ffmpeg*
		- Check with: `ffmpeg -version`
	- *ffprobe*
		- Check with: `ffprobe -version`
- To convert image files:
	- *ImageMagick*
		- Check with: `magick -version`

## Running CompConvert

1. Create the folders `in` and `out` inside the folder of this file
2. Place the files to convert inside the `in` folder
3. Run the `cc.ps1` script
4. After it has finished, the converted files are in the `out` folder

You can change some options on top of the `cc.ps1` script.
