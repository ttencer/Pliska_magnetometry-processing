#!/bin/bash
# Process and grid one selected survey field.
#
# Developed with assistance from Perplexity, an AI assistant.
# AI assistance supported code drafting, revision and troubleshooting.
# Researchers remain responsible for code review and output validation.
# Underlying Eastern Atlas processing tools were developed by Rudolf Kniess.
# 
# Usage:
#   bash process_magnetometry.sh <field> <survey_label>
#
# Example:
#   bash process_magnetometry.sh a pliska
#
# Outputs:
#   processing/<field>/   Intermediate files, merged binary and log
#   geotif/mag/std/       GeoTIFF for the selected field
#
# Requires:
#   ealdec, ealmat.m, ealgrid.m
#
# Existing outputs with the same names will be overwritten.

set -euo pipefail
export LC_ALL=C

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <field> <survey_label>" >&2
    echo "Example: bash $0 a pliska" >&2
    exit 1
fi

field="$1"
survey_label="$2"

if [[ ! "$field" =~ ^[a-zA-Z]$ ]]; then
    echo "ERROR: Field must be a single letter, such as a or A." >&2
    exit 1
fi

if [[ -z "$survey_label" || "$survey_label" == */* ]]; then
    echo "ERROR: Survey label must be non-empty and must not contain '/'." >&2
    exit 1
fi

processing_dir="processing/$field"
geotif_dir="geotif/mag/std"

for tool in ealdec ealmat.m ealgrid.m tee; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: Required program not found: $tool" >&2
        exit 1
    fi
done

ealdec_options=(
    -s0.5
    -c10
    -x-1.5
    -y0
    -V0.4
    -v
    --demean
    -d0.1
    --bin
    --drawbar=4.0
    --fixpos=0,0,0
)

shopt -s nullglob
candidates=("$field".[0-9][0-9][0-9])
profiles=()

for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
        profiles+=("$candidate")
    fi
done

if (( ${#profiles[@]} == 0 )); then
    echo "ERROR: No input files found for field $field." >&2
    echo "Expected filenames: ${field}.001, ${field}.002, etc." >&2
    exit 1
fi

mkdir -p -- "$processing_dir" "$geotif_dir"

# Use the modification date of the first input profile for output naming.
survey_date=$(date -r "${profiles[0]}" +%Y%m%d)
output_base="mag_${survey_date}.${survey_label}.${field}.std"

merged_bin="$processing_dir/${output_base}.bin"
output="$geotif_dir/${output_base}.tif"
log_file="$processing_dir/${output_base}.$(date +%Y%m%d-%H%M%S).$$.log"

# Display output in the terminal and save it to the log.
exec > >(tee -a "$log_file") 2>&1

print_command() {
    printf 'COMMAND:'
    printf ' %q' "$@"
    printf '\n'
}

run_command() {
    local status

    print_command "$@"

    if "$@"; then
        echo "STATUS: OK"
    else
        status=$?
        echo "ERROR: Command failed (exit code $status)." >&2
        exit "$status"
    fi
}

check_output() {
    local file="$1"

    if [[ ! -f "$file" || ! -s "$file" ]]; then
        echo "ERROR: Output file is missing or empty: $file" >&2
        exit 1
    fi

    echo "OUTPUT: $file"
    ls -lh -- "$file"
}

start_time=$SECONDS
processed_files=()
profile_count=${#profiles[@]}
profile_index=0

echo "=================================================="
echo "MAGNETOMETRY PROCESSING"
echo "=================================================="
echo "Started:          $(date '+%Y-%m-%d %H:%M:%S')"
echo "Working directory: $PWD"
echo "Survey label:     $survey_label"
echo "Selected field:   $field"
echo "Number of profiles: $profile_count"
echo "Processing folder: $processing_dir"
echo "GeoTIFF folder:   $geotif_dir"
echo "Log:              $log_file"
echo
echo "Input profiles:"
printf '  %s\n' "${profiles[@]}"
echo

for profile in "${profiles[@]}"; do
    profile_index=$((profile_index + 1))

    echo "=================================================="
    echo "PROFILE $profile_index/$profile_count: $profile"
    echo "=================================================="

    if [[ ! -r "$profile" || ! -s "$profile" ]]; then
        echo "ERROR: Input file is unreadable or empty: $profile" >&2
        exit 1
    fi

    decoded_bin="$processing_dir/${profile}.bin"
    corrected_bin="$processing_dir/${profile}.drift.std.bin"

    echo "Removing previous intermediate outputs for this profile."
    rm -f -- "$decoded_bin" "$corrected_bin"

    echo
    echo "[1/2] Decoding, calibration, mean subtraction and resampling"

    run_command ealdec \
        -i "$profile" \
        -o "$decoded_bin" \
        "${ealdec_options[@]}"

    check_output "$decoded_bin"

    echo
    echo "[2/2] Drift correction"

    run_command ealmat.m \
        "$decoded_bin" \
        "$corrected_bin" \
        --bin

    check_output "$corrected_bin"

    processed_files+=("$corrected_bin")

    echo
    echo "Profile completed: $profile"
    echo
done

echo "=================================================="
echo "MERGING FIELD $field"
echo "=================================================="
echo "Files to merge:"
printf '  %s\n' "${processed_files[@]}"
echo "Destination: $merged_bin"

printf 'COMMAND: cat'
printf ' %q' "${processed_files[@]}"
printf ' > %q\n' "$merged_bin"

if cat -- "${processed_files[@]}" > "$merged_bin"; then
    echo "STATUS: OK"
else
    status=$?
    echo "ERROR: Merging failed (exit code $status)." >&2
    exit "$status"
fi

check_output "$merged_bin"

echo
echo "=================================================="
echo "GRIDDING FIELD $field"
echo "=================================================="
echo "Resolution: 0.25 m"
echo "Parameters: --fill=median --gap=0.5 --extr_l=0.0 --extr_r=0.0"

if [[ -e "$output" ]]; then
    echo "Removing previous GeoTIFF: $output"
fi
rm -f -- "$output"

run_command ealgrid.m \
    --res=0.25 \
    --bin \
    --fill=median \
    --gap=0.5 \
    --extr_l=0.0 \
    --extr_r=0.0 \
    "$merged_bin" \
    "$output"

check_output "$output"

elapsed=$((SECONDS - start_time))

echo
echo "=================================================="
echo "PROCESSING COMPLETED SUCCESSFULLY"
echo "=================================================="
echo "Finished:      $(date '+%Y-%m-%d %H:%M:%S')"
echo "Elapsed time:  $((elapsed / 60)) min $((elapsed % 60)) s"
echo "Field:         $field"
echo "Profiles:      $profile_count"
echo "Merged binary: $merged_bin"
echo "GeoTIFF:       $output"
echo "Log:           $log_file"