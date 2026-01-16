#!/bin/bash -e

#export SOURCE_DATE_EPOCH=$(date -d "2026-01-01 00:00:00 UTC" +%s)

PYTHON_VERSION=$1
BUILD_SCRIPT_PATH=${2:-""}
SUFFIX=${3:-""}
EXTRA_ARGS="${@:4}" # Capture all additional arguments passed to the script
CURRENT_DIR="${PWD}"
EXIT_CODE=0

#install gcc
yum install -y gcc-toolset-13 zip unzip 
source /opt/rh/gcc-toolset-13/enable
gcc --version

# Temporary build script path
if [ -n "$BUILD_SCRIPT_PATH" ]; then
    TEMP_BUILD_SCRIPT_PATH="temp_build_script.sh"
else
    TEMP_BUILD_SCRIPT_PATH=""
fi

# Function to install a specific Python version
install_python_version() {
    local version=$1
    echo "Installing Python version: $version"
    case $version in
    "3.9" | "3.11" | "3.12")
        echo "Starting python installing..."
        yum install -y python${version} python${version}-devel python${version}-pip
        ;;
    "3.10")
        if ! python3.10 --version &>/dev/null; then
            echo "Installing dependencies required for python installation..."
            yum install -y sudo zlib-devel wget ncurses git
            echo "Installing..."
            yum install -y make cmake openssl-devel
            echo "Installing..."
            yum install -y libffi libffi-devel sqlite sqlite-devel sqlite-libs bzip2-devel
            echo "Starting python installing..."
            wget https://www.python.org/ftp/python/3.10.15/Python-3.10.15.tgz
            tar xf Python-3.10.15.tgz
            cd Python-3.10.15
            ./configure --prefix=/usr/local --enable-optimizations
            echo "Still building..."
            make -j2
            echo "Still building..."
            make altinstall
            echo "Completed..."
            cd .. && rm -rf Python-3.10.15.tgz
        fi
        ;;
    "3.13")
        if ! python3.13 --version &>/dev/null; then
            echo "Installing dependencies required for python installation..."
            yum install -y sudo zlib-devel wget ncurses git
            echo "Installing..."
            yum install -y make cmake openssl-devel
            echo "Installing..."
            yum install -y libffi libffi-devel sqlite sqlite-devel sqlite-libs bzip2-devel
            echo "Starting python installing..."
            wget https://www.python.org/ftp/python/3.13.0/Python-3.13.0.tgz
            tar xzf Python-3.13.0.tgz
            cd Python-3.13.0
            ./configure --prefix=/usr/local --enable-optimizations
            echo "Still building..."
            make -j2
            echo "Still building..."
            make altinstall
            echo "Completed..."
            cd .. && rm -rf Python-3.13.0.tgz
        fi
        ;;
    *)
        echo "Unsupported Python version: $version"
        exit 1
        ;;
    esac
}

# Install the specified Python version
install_python_version "$PYTHON_VERSION"

# Function to copy and format the build script
format_build_script() {
    if [ -n "$BUILD_SCRIPT_PATH" ]; then
        cp "$BUILD_SCRIPT_PATH" "$TEMP_BUILD_SCRIPT_PATH"

        # Modify the build script for compatibility
        sed -i 's/\bpython[0-9]\+\.[0-9]\+ -m pip /pip /g' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i 's/python[0-9]\+\.[0-9]\+/python/g' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i 's/python3 /python /g' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i 's/pip3 /pip /g' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i '/-m venv/d' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i '/bin\/activate/d' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i '/^\s*deactivate\s*$/d' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i '/yum install/{s/\(python\|python-devel\|python-pip\)\([[:space:]]\|$\)//g; s/[[:space:]]\+/ /g}' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i '/dnf install/{s/\(python\|python-devel\|python-pip\)\([[:space:]]\|$\)//g; s/[[:space:]]\+/ /g}' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i 's/\bpython3 -m pytest/pytest/g' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i "s/tox -e py[0-9]\{2,3\}\([[:space:]]*.*\)\?/tox -e py${PYTHON_VERSION//./}\1/g" "$TEMP_BUILD_SCRIPT_PATH"
        sed -i 's/^[[:space:]]*exit[[:space:]]\+0[[:space:]]*$//' "$TEMP_BUILD_SCRIPT_PATH"
    else
        echo "No build script specified, skipping copying."
    fi
}

# Function to create a virtual environment
create_venv() {
    local VENV_DIR=$1
    local python_version=$2

    "python$python_version" -m venv --system-site-packages "$VENV_DIR"
    source "$VENV_DIR/bin/activate"
}

# Function to clean up the virtual environment
cleanup() {
    local VENV_DIR=$1

    deactivate
    rm -rf "$VENV_DIR"
}

# Function to modify the metadata file after wheel creation
modify_metadata_file() {
    local wheel_path="$1"
    
    temp_dir="temp_directory"
    mkdir -p "$temp_dir"

    unzip -q "$wheel_path" -d "$temp_dir"

    local metadata_file
    metadata_file=$(find "$temp_dir" -name METADATA -path "*.dist-info/*")

    local new_classifier="Classifier: Environment :: MetaData :: IBM Python Ecosystem"

    if grep -q "^$new_classifier$" "$metadata_file"; then
        echo "Classifier already exists in $wheel_path — no changes made."
    else
        awk -v new_classifier="$new_classifier" '
            BEGIN {
                found_classifier = 0
                output = ""
            }
            /^Classifier:/ {
                found_classifier = 1
                last_classifier_line = NR
            }
            {
                lines[NR] = $0
            }
            END {
                if (found_classifier) {
                    for (i = 1; i <= NR; i++) {
                        print lines[i]
                        if (i == last_classifier_line) {
                            print new_classifier
                        }
                    }
                } else {
                    print new_classifier
                    for (i = 1; i <= NR; i++) {
                        print lines[i]
                    }
                }
            }
        ' "$metadata_file" > "$metadata_file.tmp" && mv "$metadata_file.tmp" "$metadata_file"

        wheel_file_name=$(basename "$wheel_path")
        cd "$temp_dir" && zip -q -r "$CURRENT_DIR/$wheel_file_name" ./*
        echo "Added IBM classifier to $wheel_path"
    fi

    rm -rf "$CURRENT_DIR/$temp_dir"
}

# Format the build script if it's non-empty
if [ -n "$BUILD_SCRIPT_PATH" ]; then
    format_build_script
fi

echo "Processing Package with Python $PYTHON_VERSION"

# Create and activate virtual environment
VENV_DIR="$CURRENT_DIR/pyvenv_$PYTHON_VERSION"
create_venv "$VENV_DIR" "$PYTHON_VERSION"

echo "=============== Running package build-script starts =================="

if [ -n "$TEMP_BUILD_SCRIPT_PATH" ]; then
    echo "Installing required dependencies..."
    python$PYTHON_VERSION -m pip install --upgrade pip wheel build pytest nox tox requests setuptools
    echo "Installing required dependencies completed..."

    package_dir=$(grep -oP '(?<=^PACKAGE_DIR=).*' "$TEMP_BUILD_SCRIPT_PATH" | tr -d '"')
    package_url=$(grep -oP '(?<=^PACKAGE_URL=).*' "$TEMP_BUILD_SCRIPT_PATH" | tr -d '"')
    package_name=$(basename "$package_url" .git)

    echo "Running the build script..."
    source "$TEMP_BUILD_SCRIPT_PATH" "$EXTRA_ARGS"
    
else
    echo "No build script to run, skipping execution."
fi

# Checking if wheel is generated through script itself
cd $CURRENT_DIR
if ls *.whl 1>/dev/null 2>&1; then
    echo "Wheel file already exist in the current directory:"
    ls *.whl
else
    # Navigating to the package directory to build wheel
    if [ -d "$package_dir" ]; then
        echo "Navigating to the package directory: $package_dir"
        cd "$package_dir"
    else
        echo "package_dir not found, Navigating to package_name: $package_name"
        cd "$package_name"
    fi

    echo "=============== Building wheel =================="

    if ! python -m build --wheel --no-isolation --outdir="$CURRENT_DIR/"; then
        echo "============ Wheel Creation Failed for Python $PYTHON_VERSION (without isolation) ================="
        echo "Attempting to build with isolation..."
        if ! python -m build --wheel --outdir="$CURRENT_DIR/"; then
            echo "============ Wheel Creation Failed for Python $PYTHON_VERSION ================="
            EXIT_CODE=1
        fi
    fi
fi

cd "$CURRENT_DIR"

# ----------------- Auditwheel Repair Section -----------------
LOGFILE="$CURRENT_DIR/auditwheel.log"
WHEELHOUSE="$CURRENT_DIR/wheelhouse"
mkdir -p "$WHEELHOUSE"

wheel_count=$(ls *.whl 2>/dev/null | wc -l)
echo "Wheel count detected: $wheel_count"

if [ "$wheel_count" -eq 1 ]; then
    wheel_file=$(ls *.whl)
    echo "=============== Running auditwheel repair on $wheel_file =================="
    pip install auditwheel patchelf

    audit_output=$(auditwheel repair "$wheel_file" --wheel-dir "$WHEELHOUSE" 2>&1) || true

    echo "$audit_output" > "$LOGFILE"
    echo "Auditwheel output saved to auditwheel.log"

    if echo "$audit_output" | grep -q "ValueError: Cannot repair wheel"; then
        echo "Auditwheel errored for $wheel_file"
        touch "$CURRENT_DIR/audit_wheel_errored"
        echo "$audit_output"
    elif echo "$audit_output" | grep -q "This does not look like a platform wheel"; then
        echo "Auditwheel skipped for $wheel_file (pure Python wheel)"
        touch "$CURRENT_DIR/audit_wheel_skipped"
    else
        echo "Auditwheel succeeded for $wheel_file"
        # Uncomment below if you want to use repaired wheel
        # repaired_wheel=$(ls "$WHEELHOUSE"/*.whl)
        # wheel_file="$repaired_wheel"
        echo "Running .so license injection and adding suffix"
        python license_suffix.py $WHEELHOUSE/*.whl "${SUFFIX}"
        #echo "Running sha256"
        # SHA256=$(sha256sum $WHEELHOUSE/*.whl)
        # echo "$SHA256"
        # SHA256_FILE="${CURRENT_DIR}/$(basename "$wheel_file").sha256"
        # echo "$SHA256" > "$SHA256_FILE"
        # echo "SHA256 for $(basename "$wheel_file") saved to $SHA256_FILE"
        #for wheel in "$WHEELHOUSE"/*.whl; do
            # Skip if no wheels are found
            #[ -e "$wheel" ] || continue

            #sha256sum "$wheel" > "${wheel}.sha256"
        #done
    fi

else
    echo "Wheel count is $wheel_count (0 or more than 1), marking as errored"
    touch "$CURRENT_DIR/audit_wheel_errored"
    echo "$audit_output"
fi

echo "Auditwheel section completed."
# ----------------- End of Auditwheel Section -----------------


# Optionally modify metadata
if ls *.whl 1>/dev/null 2>&1; then
    echo "=============== Modifying Metadata file =================="
    wheel_file=$(ls *.whl 1>/dev/null 2>&1 && echo *.whl)
    #modify_metadata_file "$wheel_file"
fi

# Clean up virtual environment
cleanup "$VENV_DIR"

# Remove temporary build script
[ -n "$TEMP_BUILD_SCRIPT_PATH" ] && rm "$CURRENT_DIR/$TEMP_BUILD_SCRIPT_PATH"

exit $EXIT_CODE

