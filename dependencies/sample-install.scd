(
// Assume d.requiredSounds has been set (e.g., d.requiredSounds = ["piano", "drums", "bass"])
// Configuration
var soundsDir = Platform.userAppSupportDir +/+ "sounds";
var targetDir = soundsDir +/+ "twm_samples";
var downloadURL = "https://github.com/twmcdunn/samples/releases/latest/download/samples.zip";
var tempDir = Platform.defaultTempDir;
var zipPath = tempDir +/+ "twm_samples.zip";
var extractDir = tempDir +/+ "twm_samples_extract";
var isWindows = thisProcess.platform.name == \windows;
var requiredSounds = d.requiredSounds ? []; // Get from d, default to empty array
var allExist = true;
var missingFolders = [];

// Helper function to execute shell commands with error handling
var execCommand = { |cmd, errorMsg = "Command failed"|
	var pipe, result, line, output = "";
	try {
		pipe = Pipe.new(cmd, "r");
		while { line = pipe.getLine; line.notNil } {
			output = output ++ line ++ "\n";
		};
		pipe.close;
		output;
	} {|error|
		("ERROR: " ++ errorMsg ++ "\n" ++ error.errorString).postln;
		nil;
	};
};

// Helper function to clean up on error
var cleanup = {
	"Cleaning up temporary files...".postln;
	try {
		if(File.exists(extractDir), {
			if(isWindows, {
				execCommand.value(
					"powershell -Command \"Remove-Item -Path '%' -Recurse -Force\"".format(extractDir),
					"Failed to remove extraction directory"
				);
			}, {
				execCommand.value("rm -rf '%'".format(extractDir), "Failed to remove extraction directory");
			});
		});
		if(File.exists(zipPath), {
			if(isWindows, {
				execCommand.value(
					"powershell -Command \"Remove-Item -Path '%' -Force\"".format(zipPath),
					"Failed to remove zip file"
				);
			}, {
				execCommand.value("rm '%'".format(zipPath), "Failed to remove zip file");
			});
		});
	} {|error|
		("Warning: Cleanup failed - " ++ error.errorString).postln;
	};
};

// Step 1: Check if required sounds already exist
"Checking for required sounds...".postln;
if(File.exists(targetDir), {
	requiredSounds.do { |folderName|
		var folderPath = targetDir +/+ folderName;
		if(File.exists(folderPath).not, {
			allExist = false;
			missingFolders = missingFolders.add(folderName);
		});
	};

	if(allExist, {
		"All required sounds already installed. Exiting.".postln;
		if(d[\onComplete].notNil, {
			d[\onComplete].value;
		});
		nil; // Exit script
	}, {
		"Missing folders: %".format(missingFolders).postln;
		// Continue to GUI prompt
	});
}, {
	"twm_samples directory does not exist yet.".postln;
	allExist = false;
	// Continue to GUI prompt
});

// Only proceed if we need to install
if(allExist.not, {
	// Step 2: Show GUI confirmation dialog
	var window, installFunc, proceeding = false;   // closing the window only cancels before Proceed

	installFunc = {
		var success = true;

		// Close the window
		{ window.close; }.defer;

		"Starting installation...".postln;

		// Step 3: Create directories
		try {
			if(File.exists(soundsDir).not, {
				File.mkdir(soundsDir);
				"Created sounds directory: %".format(soundsDir).postln;
			});

			if(File.exists(targetDir).not, {
				File.mkdir(targetDir);
				"Created directory: %".format(targetDir).postln;
			}, {
				"Directory already exists: %".format(targetDir).postln;
			});

			if(File.exists(extractDir).not, {
				File.mkdir(extractDir);
			});
		} {|error|
			("ERROR: Failed to create directories - " ++ error.errorString).postln;
			success = false;
		};

		if(success, {
			// Step 4: Download the zip file
			var downloadResult;
			"Downloading samples from GitHub...".postln;

			if(isWindows, {
				downloadResult = execCommand.value(
					"powershell -Command \"Invoke-WebRequest -Uri '%' -OutFile '%'\"".format(downloadURL, zipPath),
					"Download failed"
				);
			}, {
				downloadResult = execCommand.value(
					"curl -L -o '%' '%'".format(zipPath, downloadURL),
					"Download failed"
				);
			});

			if(downloadResult.isNil, {
				success = false;
			}, {
				"Download complete.".postln;
			});
		});

		if(success and: { File.exists(zipPath).not }, {
			"ERROR: Zip file was not downloaded successfully.".postln;
			success = false;
		});

		if(success, {
			var extractResult;
			// Step 5: Unzip the file
			"Extracting archive...".postln;

			if(isWindows, {
				extractResult = execCommand.value(
					"powershell -Command \"Expand-Archive -Path '%' -DestinationPath '%' -Force\"".format(zipPath, extractDir),
					"Extraction failed"
				);
			}, {
				extractResult = execCommand.value(
					"unzip -q '%' -d '%'".format(zipPath, extractDir),
					"Extraction failed"
				);
			});

			if(extractResult.isNil, {
				success = false;
			}, {
				"Extraction complete.".postln;
			});
		});

		if(success, {
			// Step 6: Find the extracted folder
			// Ignore macOS/git junk (__MACOSX, .DS_Store, .git) when locating sample folders
			var isJunk = { |item|
				var name = if(item.isFolder, { item.folderName }, { item.fileName });
				name.beginsWith("__MACOSX") or: { name.beginsWith(".") };
			};
			var extractedContents = PathName(extractDir).entries.reject(isJunk);
			var sourceFolder;

			if(extractedContents.size == 0, {
				"ERROR: No contents found in extracted archive.".postln;
				success = false;
			}, {
				sourceFolder = if(extractedContents.size == 1 and: { extractedContents[0].isFolder }, {
					extractedContents[0].fullPath;
				}, {
					extractDir;
				});

				"Source folder: %".format(sourceFolder).postln;

				// Step 7: Move immediate child folders to twm_samples
				"Moving sample folders...".postln;
				try {
					PathName(sourceFolder).entries.reject(isJunk).do { |item|
						if(item.isFolder, {
							var folderName = item.folderName;
							var destPath = targetDir +/+ folderName;

							if(File.exists(destPath).not, {
								var moveCmd, moveResult;
								if(isWindows, {
									moveCmd = "powershell -Command \"Move-Item -Path '%' -Destination '%'\"".format(item.fullPath, destPath);
								}, {
									moveCmd = "mv '%' '%'".format(item.fullPath, destPath);
								});
								moveResult = execCommand.value(moveCmd, "Failed to move " ++ folderName);
								if(moveResult.notNil, {
									"Moved: %".format(folderName).postln;
								});
							}, {
								"Skipped (already exists): %".format(folderName).postln;
							});
						});
					};
				} {|error|
					("ERROR: Failed to move folders - " ++ error.errorString).postln;
					success = false;
				};
			});
		});

		// Step 8: Clean up
		cleanup.value();

		if(success, {
			"Installation complete! Samples are in: %".format(targetDir).postln;
			// Call the completion callback if it exists
			if(d[\onComplete].notNil, {
				d[\onComplete].value;
			});
		}, {
			"Installation failed. Please check the errors above.".postln;
		});
	};

	// Create GUI window
	{
		window = Window.new("Install TWM Samples", Rect(400, 400, 400, 200))
		.front
		.onClose_({ if(proceeding.not) { "Installation cancelled.".postln } });

		window.layout = VLayout(
			StaticText().string_("This script will download and install sample folders\nto your SuperCollider user directory.\n\nRequired folders: %\n\nLocation: %".format(
				if(requiredSounds.size > 0, { requiredSounds.join(", ") }, { "all available" }),
				targetDir
			))
			.align_(\center),

			HLayout(
				Button()
				.states_([["Cancel"]])
				.action_({ window.close; }),
				Button()
				.states_([["Proceed"]])
				.action_({ proceeding = true; installFunc.value; })
			)
		);
	}.defer;
});
)