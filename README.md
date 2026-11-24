# Magnetometry processing workflow

A Bash script for processing and gridding one selected magnetometry survey field at a time using Eastern Atlas software.

The workflow was prepared for data acquired using a ten-probe LeaMax fluxgate gradiometer equipped with Foerster FEREX CON650 probes. The script automates existing tools; it does not implement new decoding, drift-correction or gridding algorithms.

## Download the script

[View the Bash script](./process_magnetometry.sh)

To download it, open the link above and click the download icon
(Download raw file) in the upper-right corner of the file view.

## Requirements

* Bash (run with `bash`, not `sh`).
* A Linux-compatible environment with GNU command-line utilities, including `date`, `mkdir`, `rm`, `cat`, `ls` and `tee`.
* Eastern Atlas processing tools available on `PATH`:

  * `ealdec`: version dated 11 June 2018.
  * `ealmat.m`: version dated 1 November 2019, with `ea_fkt` dated 16 March 2018.
  * `ealgrid.m`: version not recorded in this documentation.
* Any additional runtime dependencies required by the installed Eastern Atlas tools.

The Eastern Atlas processing tools were developed by Rudolf Kniess (Eastern Atlas; r.kniess@eastern-atlas.de) and supplied with the magnetometer system. They are not included in this repository. Their licensing, redistribution conditions and availability must be confirmed with the supplier. Publishing this wrapper does not grant access to, or redistribution rights for, those tools.

## Input files

Run the script from the directory containing the raw binary survey files. Each input filename must contain one letter, a dot and three digits:

```text
a.001
a.002
a.003
b.001
b.002
```

Only files matching the selected field are processed. Identifiers are case-sensitive: `a` and `A` are different fields. Profiles are processed in filename order using the C locale.

The script does not search subdirectories.

## Quick start

From the directory containing the input measurements:

```bash
bash process_magnetometry.sh a pliska 
```

If the script is stored elsewhere, provide its path while remaining in the input-data directory:

```bash
bash /path/to/process_magnetometry.sh a pliska 
```

Arguments:

|Argument|Example|Meaning|
|-|-|-|
|`field`|`a`|One letter identifying the field to process|
|`survey_label`|`pliska `|Non-empty label used in output filenames; must not contain `/`|

The example processes `a.001`, `a.002`, etc., merges their corrected data and exports one raster for field `a`. Files belonging to field `b` are not included.

To process another field, run the script again:

```bash
bash process_magnetometry.sh b pliska 
```

The survey label is not a directory argument. All input and output paths are interpreted relative to the current working directory.

## Processing steps

For every profile in the selected field, the script:

1. Checks that the input is readable and non-empty.
2. Decodes the measurements using `ealdec`, including calibration, mean subtraction and distance resampling.
3. Applies drift correction using `ealmat.m` with binary input/output enabled.
4. Checks that each expected intermediate output exists and is non-empty.

After all selected profiles have been processed, the script:

5. Concatenates the corrected binary files using `cat`.
6. Grids the combined field using `ealgrid.m` at a requested cell size of 0.25 m.
7. Checks that the final output file exists and is non-empty.

The merge includes only files processed in the current run. Compatibility of binary concatenation with other software versions or binary formats must be verified before adapting the workflow.

## Processing parameters

The settings below are hard-coded in the script and must be reviewed before applying it to a different instrument configuration or dataset.

### Decoding: ealdec

|Option|Setting|Description|
|-|-|-|
|`-s`|`0.5`|Sensor spacing, m|
|`-c`|`10`|Number of channels|
|`-x`|`-1.5`|Longitudinal position offset, m|
|`-y`|`0`|Lateral position offset, m|
|`-V`|`0.4`|Calibration factor, mV/nT|
|`-v`|enabled|Verbose output|
|`--demean`|enabled|Mean subtraction|
|`-d`|`0.1`|Resampling interval by stacking, m|
|`--bin`|enabled|Binary output|
|`--drawbar`|`4.0`|Drawbar-length parameter, m|
|`--fixpos`|`0,0,0`|Fixed North, East and height shifts, m|

### Drift correction: ealmat.m

```text
--bin
```

No additional optional arguments are supplied. Drift-correction settings not specified by the wrapper depend on the installed software defaults. The wrapper does not document the underlying fitting order, window size or other algorithm-specific defaults.

### Gridding: ealgrid.m

```text
--res=0.25
--bin
--fill=median
--gap=0.5
--extr\_l=0.0
--extr\_r=0.0
```

The requested cell size is 0.25 m. Other options are reported verbatim; consult the relevant tool documentation for their precise interpretation.

## Output structure

Example for field `a` and survey label `pliska `:

```text
measurement\_directory/
|-- a.001
|-- a.002
|-- processing/
|   `-- a/
|       |-- a.001.bin
|       |-- a.001.drift.std.bin
|       |-- a.002.bin
|       |-- a.002.drift.std.bin
|       |-- mag\_YYYYMMDD.pliska .a.std.bin
|       `-- mag\_YYYYMMDD.pliska .a.std.TIMESTAMP.PID.log
`-- geotif/
    `-- mag/
        `-- std/
            `-- mag\_YYYYMMDD.pliska .a.std.tif
```

* `\*.bin`: decoded measurements.
* `\*.drift.std.bin`: drift-corrected profiles.
* `mag\_\*.std.bin`: merged corrected measurements for the selected field.
* `\*.tif`: final gridded magnetogram.
* `\*.log`: processing messages and command output.

`YYYYMMDD` is obtained from the modification time of the first selected input profile. It is not necessarily the survey acquisition date. Changing file timestamps can therefore change output names.

Intermediate files are retained; no temporary directory is used.

## Terminal output and logs

The supplied script uses internal logging:

```bash
exec > >(tee -a "$log\_file") 2>\&1
```

After logging is initialized, standard output and standard error are displayed in the terminal and copied to a timestamped log in `processing/<field>/`. Checks performed before logging is initialized are displayed only in the terminal.

Messages include selected input files, commands, processing steps, output paths, file sizes and elapsed time. External programs may buffer their own output, so some messages may appear in batches.

For additional shell tracing:

```bash
bash -x process\_magnetometry.sh a pliska 
```

Do not add a second logging wrapper unless needed. If switching to external `tee` logging, first remove the internal redirection and update the log-related messages accordingly.

## Output checks and safety

* Required processing executables and `tee` are checked before processing.
* A reported command failure or a missing/empty expected output stops the run.
* Existing decoded and corrected files for each selected profile are removed before they are recreated.
* The merged binary output is overwritten.
* An existing GeoTIFF with the same name is deleted before gridding, preventing a stale file from passing the output check.
* Back up existing outputs before rerunning. If processing fails after deletion, the previous output is not restored.
* The log records failures that occur after log initialization. Partially generated files may remain after a failed run.

The export check verifies command completion and the existence of a non-empty output. It does not validate TIFF structure, coordinate reference system, georeferencing, raster values or scientific correctness. The script does not explicitly assign a coordinate reference system; verify the exported raster against the survey metadata.

## Troubleshooting

### Required program not found

Install or configure the corresponding Eastern Atlas software and ensure it is available on `PATH`:

```bash
command -v ealdec
command -v ealmat.m
command -v ealgrid.m
```

### No input files found

Check the current working directory, filename pattern and letter case. For field `a`, filenames must match `a.001`, `a.002`, etc.

### Permission errors when creating output folders

The supplied script uses relative output paths (`processing/<field>` and `geotif/mag/std`). Run it in a directory where you have write permission.

### Drift-correction input format errors

The wrapper requests binary output from `ealdec` and passes `--bin` to `ealmat.m`. If loading still fails, inspect the decoded file and confirm compatibility between the installed tool versions.

## Data availability and reproducibility

Publishing this automation script does not by itself provide the measurements or the external processing software. Compatible survey files, the processing tools and their runtime dependencies are required to reproduce the workflow.

Study-specific access to magnetograms and other research datasets is described separately in the associated manuscript. This README does not grant access to restricted datasets.

## Attribution and AI assistance

The underlying Eastern Atlas tools (`ealdec`, `ealmat.m`, `ea\_fkt` and `ealgrid.m`) were developed by Rudolf Kniess, Eastern Atlas.

The Bash automation script and this README were developed with assistance from Perplexity, an AI assistant. AI assistance supported code drafting, revision, troubleshooting and preparation of the documentation.

This acknowledgement applies to the automation wrapper and its documentation, not to the underlying Eastern Atlas tools. AI assistance does not constitute independent validation of the code or scientific results. The researchers remain responsible for code review, verification of its behaviour and assessment of the resulting data.

