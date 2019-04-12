#! /bin/bash
#
# server.sh
# Copyright (C) 2019 Morten Houmøller Nygaard <mortzdk@gmail.com>
#
# Distributed under terms of the MIT license.
#
# TODO: support role standalone

# DEFAULT VALUES
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
DEBUG="false"
ADDRESS="0.0.0.0"

# Get platform script is running on
unameOut="$(uname -s)"
case "${unameOut}" in
    Linux*)     PLATFORM="linux" PLATFORM_NAME="linux"; EXT="";;
    Darwin*)    PLATFORM="mac" PLATFORM_NAME="mac" EXT="";;
    CYGWIN*)    PLATFORM="win"; PLATFORM_NAME="windows" EXT=".exe";;
    *)          echo "ERROR: Unsupported platform '$unameOut'." >&2; exit 1
esac

archOut="$(arch)"
case "${archOut}" in
    i686*)      ARCH="32";;
    x86_64*)    ARCH="64";;
    *)          echo "ERROR: Unsupported architecture '$archOut'." >&2; exit 1
esac

# Show how to use server script
function show_info() {
    echo -e "./server.sh\n\t-i Shows the information about the arguments available for the server\n\t-s Start a standalone selenium server\n\t-h [HUB_HOST] Start a selenium server hub or passes the address to the hub\n\t-n Start a selenium server node\n\t-j {JAR_PATH} The path to a selenium server jar. If none is present, the newest in the jars folder will be used.\n\t-a {ADDRESS} The address for which the server should run. Default to 0.0.0.0.\n\t-p {PORT} The port that the server should run on. Default 4444 for hub and 5555 for node\n\t-d Enable debug mode\n\t-c {CONFIG_PATH} The path to a selenium config json file. If none is present, a config file will be generated based on the environment.";
    exit 1
}

# If no parameters are given show info
if [ $# -eq 0 ]; then
    show_info
fi

# Parse options to script
while getopts a:j:p:c:shni option
do
case "${option}"
in
a) ADDRESS=${OPTARG};;
i) show_info;;
j) JAR=${OPTARG};;
p) PORT=${OPTARG};;
c) CONFIG=${OPTARG};;
h) ROLE="hub"; HUB=${OPTARG};;
n) ROLE="node";;
s) ROLE="standalone";;
d) DEBUG="true";;
esac
done

# If neither node or hub parameter were given throw error and show info 
if [[ -z $ROLE ]]; then
    echo "ERROR: Either -s, -n or -h must be used to specify whether server should run in standalone, node or hub mode" >&2
    echo ""
    show_info
fi

# Generate application name if none was given
NAME="selenium-$ROLE"

# Function that checks whether command is available and installed
function is_installed()
{
    if ! [ -x "$(command -v $1)" ]; then
        echo "ERROR: '$1' is not installed." >&2
        exit 1
    fi
}

# Function that compares semver versions. 0='=', 1='>', 2='<'
function compare_versions() {

    # Trivial v1 == v2 test based on string comparison
    [[ "$1" == "$2" ]] && return 0

    # Local variables
    local regex="^(.*)-r([0-9]*)$" va1=() vr1=0 va2=() vr2=0 len i IFS="."

    # Split version strings into arrays, extract trailing revisions
    if [[ "$1" =~ ${regex} ]]; then
        va1=(${BASH_REMATCH[1]})
        [[ -n "${BASH_REMATCH[2]}" ]] && vr1=${BASH_REMATCH[2]}
    else
        va1=($1)
    fi
    if [[ "$2" =~ ${regex} ]]; then
        va2=(${BASH_REMATCH[1]})
        [[ -n "${BASH_REMATCH[2]}" ]] && vr2=${BASH_REMATCH[2]}
    else
        va2=($2)
    fi

    # Bring va1 and va2 to same length by filling empty fields with zeros
    (( ${#va1[@]} > ${#va2[@]} )) && len=${#va1[@]} || len=${#va2[@]}
    for ((i=0; i < len; ++i)); do
        [[ -z "${va1[i]}" ]] && va1[i]="0"
        [[ -z "${va2[i]}" ]] && va2[i]="0"
    done

    # Append revisions, increment length
    va1+=($vr1)
    va2+=($vr2)
    len=$((len+1))

    # Compare version elements, check if v1 > v2 or v1 < v2
    for ((i=0; i < len; ++i)); do
        if (( 10#${va1[i]} > 10#${va2[i]} )); then
            return 1
        elif (( 10#${va1[i]} < 10#${va2[i]} )); then
            return 2
        fi
    done

    # All elements are equal, thus v1 == v2
    return 0
}

# Function to extract semver version from string
function semver_version {
    local version=$1
    local SEMVER_REGEX="(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(\\.(0|[1-9][0-9]*))?(\\-[0-9A-Za-z-]+(\\.[0-9A-Za-z-]+)*)?(\\+[0-9A-Za-z-]+(\\.[0-9A-Za-z-]+)*)?"

    if [[ "$version" =~ $SEMVER_REGEX ]]; then
        # if a second argument is passed, store the result in var named by $2
        if [ "$#" -eq "2" ]; then
            MAJOR=${BASH_REMATCH[1]}
            MINOR=${BASH_REMATCH[2]}
            PATCH=${BASH_REMATCH[3]}
            PRERE=${BASH_REMATCH[4]}
            BUILD=${BASH_REMATCH[5]}
            
            eval "$2=\"${BASH_REMATCH[0]}\""
        else
            echo "$version"
        fi
    fi
}

function check_selenium {
    wget -q --no-verbose -O /tmp/SELENIUM_RELEASE "https://selenium-release.storage.googleapis.com/"
    local versions=`cat /tmp/SELENIUM_RELEASE | grep -Po "selenium-server-standalone-[\d+][\.\d+]*jar"`
    rm /tmp/SELENIUM_RELEASE 
    semver_version "$versions[0]" "current_version"
    for v in $versions
    do
        semver_version "$v" "ver"
        compare_versions "$ver" "$current_version"

		if [[ "$?" = "1" ]];
		then
			current_version=$ver
		fi
    done

    semver_version "$current_version" "SELENIUM_VERSION"
    
    if ! [[ -f $DIR/jars/selenium-server-standalone-$SELENIUM_VERSION.jar ]]; then
        wget --no-verbose -O "$DIR/jars/selenium-server-standalone-$SELENIUM_VERSION.jar" "https://selenium-release.storage.googleapis.com/$MAJOR.$MINOR/selenium-server-standalone-$SELENIUM_VERSION.jar"
    fi

    eval "$1+=\"$DIR/jars/selenium-server-standalone-$SELENIUM_VERSION.jar\""
}

# Check if chrome/chromium is installed, download corresponding driver and
# generate capabilities.
function check_chrome {
    local CHROME_STRING=""
    local CHROME_MAYOR_VERSION=""
    local CHROME_DRIVER_VERSION=""

    if [[ -x "$(command -v 'google-chrome')" ]]
    then
        CHROME_PATH=$(which google-chrome)
        CHROME_STRING=$($CHROME_PATH --version)
    elif [[ -x "$(command -v 'google-chrome-stable')" ]]
    then
        CHROME_PATH=$(which google-chrome)
        CHROME_STRING=$($CHROME_PATH --version)
    elif [[ -x "$(command -v 'chromium-browser')" ]]
    then
        CHROME_PATH=$(which chromium-browser)
        CHROME_STRING=$($CHROME_PATH --version)
    else
        return
    fi

    CHROME_VERSION=$(echo "${CHROME_STRING}" | grep -oP "\d+\.\d+\.\d+\.\d+")
    CHROME_MAYOR_VERSION=$(echo "${CHROME_VERSION%%.*}")
    wget -q --no-verbose -O /tmp/LATEST_RELEASE "https://chromedriver.storage.googleapis.com/LATEST_RELEASE_${CHROME_MAYOR_VERSION}"
    CD_VERSION=$(cat "/tmp/LATEST_RELEASE") 
    rm /tmp/LATEST_RELEASE 
    if [ -z "$CHROME_DRIVER_VERSION" ]; 
    then
        CHROME_DRIVER_VERSION="${CD_VERSION}"; 
    fi 
    CD_VERSION=$(echo $CHROME_DRIVER_VERSION)
    echo "Using chromedriver version: "$CD_VERSION
    if [ ! -f "$DIR/drivers/chromedriver-$CD_VERSION$EXT" ]; then
        wget --no-verbose -O "/tmp/chromedriver_${PLATFORM}${ARCH}.zip" "https://chromedriver.storage.googleapis.com/$CD_VERSION/chromedriver_${PLATFORM}${ARCH}.zip"
        rm -f "$DIR/drivers/chromedriver$EXT"
        unzip "/tmp/chromedriver_${PLATFORM}${ARCH}.zip" -d "$DIR/drivers"
        rm "/tmp/chromedriver_${PLATFORM}${ARCH}.zip"
        mv "$DIR/drivers/chromedriver$EXT" "$DIR/drivers/chromedriver-$CD_VERSION$EXT"
        chmod 755 "$DIR/drivers/chromedriver-$CD_VERSION$EXT"
        ln -fs "$DIR/drivers/chromedriver-$CD_VERSION$EXT" "$DIR/drivers/chromedriver$EXT"
    fi

    local cap=$(cat <<-END
    {
        \"version\": \"$CHROME_VERSION\",
        \"browserName\": \"chrome\",
        \"platformName\": \"$PLATFORM_NAME\",
        \"maxInstances\": 5,
        \"seleniumProtocol\": \"WebDriver\",
        \"applicationName\": \"$NAME\"
    },
END
)
    eval "$1+=\"$cap\""
}

# Check if firefox is installed, download corresponding driver and generate
# capabilities.
function check_firefox {
    if ! [[ -x "$(command -v 'firefox')" ]]
    then
        return
    fi

    FIREFOX_PATH=$(which firefox)
    semver_version `$FIREFOX_PATH --version` "FIREFOX_VERSION"

    semver_version `curl --silent "https://api.github.com/repos/mozilla/geckodriver/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'` "GK_VERSION"

    echo "Using GeckoDriver version: "$GK_VERSION
    if [ ! -f "$DIR/drivers/geckodriver-$GK_VERSION$EXT" ]; then
        wget --no-verbose -O "/tmp/geckodriver.tar.gz" "https://github.com/mozilla/geckodriver/releases/download/v$GK_VERSION/geckodriver-v$GK_VERSION-${PLATFORM}${ARCH}.tar.gz"
        rm -f "$DIR/drivers/geckodriver$EXT"
        tar -C "$DIR/drivers" -zxf "/tmp/geckodriver.tar.gz"
        rm "/tmp/geckodriver.tar.gz"
        mv "$DIR/drivers/geckodriver$EXT" "$DIR/drivers/geckodriver-$GK_VERSION$EXT"
        chmod 755 "$DIR/drivers/geckodriver-$GK_VERSION$EXT"
        ln -fs "$DIR/drivers/geckodriver-$GK_VERSION$EXT" "$DIR/drivers/geckodriver$EXT"
    fi

    local cap=$(cat <<-END
    {
        \"marionette\": true,
        \"version\": \"$FIREFOX_VERSION\",
        \"browserName\": \"firefox\",
        \"platformName\": \"$PLATFORM_NAME\",
        \"maxInstances\": 5,
        \"seleniumProtocol\": \"WebDriver\",
        \"moz:firefoxOptions\" : {
            \"log\": {
                \"level\": \"trace\"
            }
        },
        \"applicationName\": \"$NAME\"
    },
END
)
    eval "$1+=\"$cap\""
}

# Check if opera is installed, download corresponding driver and generate
# capabilities.
function check_opera {
    if ! [[ -x "$(command -v 'opera')" ]]
    then
        return
    fi

    OPERA_PATH=$(which opera)
    local OPERA_STRING=$($OPERA_PATH --version)
    local OPERA_VERSION_STRING=$(echo "$OPERA_STRING" | grep -oP "\d+\.\d+\.\d+\.\d+")

    compare_versions "$OPERA_VERSION_STRING" "12.15"
    if [[ "$?" = "1" ]];
    then
        semver_version `curl --silent "https://api.github.com/repos/operasoftware/operachromiumdriver/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'` "OD_VERSION"

        echo "Using OperaChromiumDriver version: "$OD_VERSION

        if [ ! -f "$DIR/drivers/operachromiumdriver-$OD_VERSION$EXT" ]; then
            wget --no-verbose -O "/tmp/operachromiumdriver_${PLATFORM}${ARCH}.zip" "https://github.com/operasoftware/operachromiumdriver/releases/download/v.$OD_VERSION/operadriver_${PLATFORM}${ARCH}.zip"
            rm -f "$DIR/drivers/operachromiumdriver$EXT"
            unzip "/tmp/operachromiumdriver_${PLATFORM}${ARCH}.zip" -d "/tmp/operachromiumdriver"
            rm "/tmp/operachromiumdriver_${PLATFORM}${ARCH}.zip"
            mv "/tmp/operachromiumdriver/operadriver_${PLATFORM}${ARCH}/operadriver$EXT" "$DIR/drivers/operachromiumdriver-$OD_VERSION$EXT"
            chmod 755 "$DIR/drivers/operachromiumdriver-$OD_VERSION$EXT"
            ln -fs "$DIR/drivers/operachromiumdriver-$OD_VERSION$EXT" "$DIR/drivers/operachromiumdriver$EXT"
            rm -r "/tmp/operachromiumdriver"
        fi
    else
        return
    fi

    local cap=$(cat <<-END
    {
        \"version\": \"$OPERA_VERSION_STRING\",
        \"browserName\": \"opera\",
        \"platformName\": \"$PLATFORM_NAME\",
        \"maxInstances\": 5,
        \"seleniumProtocol\": \"WebDriver\",
        \"applicationName\": \"$NAME\"
    },
END
)

    eval "$1+=\"$cap\""
}

is_installed "arch"
is_installed "java"
is_installed "wget"
is_installed "unzip"
is_installed "tar"

# Generate nodeConfig parameter
if [[ $ROLE = "node" ]]; then
    if [[ -z $PORT ]]; then
        PORT="5555"
    fi

    if [[ -z $CONFIG ]]; then
        CONF=$(cat <<-END 
        {
            "proxy": "org.openqa.grid.selenium.proxy.DefaultRemoteProxy",
            "maxSession": 5,
            "host": "$ADDRESS",
            "port": $PORT,
            "register": true,
            "registerCycle": 5000,
            "hub": "$HUB",
            "nodeStatusCheckTimeout": 5000,
            "nodePolling": 5000,
            "role": "$ROLE",
            "unregisterIfStillDownAfter": 60000,
            "downPollingLimit": 2,
            "debug": false,
            "servlets" : [],
            "withoutServlets": [],
            "custom": {},
            "debug": $DEBUG,
            "capabilities": [
END
);

        check_chrome "CONF"
        check_firefox "CONF"
        check_opera "CONF"
        CONF=${CONF%?};
        CONF+="]}"

        echo $CONF > "$DIR/configs/$ROLE.config.json"

        CONFIG="-nodeConfig $DIR/configs/$ROLE.config.json"
    else
        CONFIG="-nodeConfig $config"
    fi
fi

# Generate hubConfig parameter
if [[ $ROLE = "hub" ]]; then
    if [[ -z $PORT ]]; then
        PORT="4444"
    fi

    if [[ -z $CONFIG ]]; then
        CONF=$(cat <<-END
        {
            "host": "$ADDRESS",
            "port": $PORT,
            "newSessionWaitTimeout": -1,
            "servlets" : [],
            "withoutServlets": [],
            "custom": {},
            "capabilityMatcher": "org.openqa.grid.internal.utils.DefaultCapabilityMatcher",
            "registry": "org.openqa.grid.internal.DefaultGridRegistry",
            "throwOnCapabilityNotPresent": true,
            "cleanUpCycle": 5000,
            "role": "$ROLE",
            "debug": $DEBUG,
            "browserTimeout": 0,
            "timeout": 1800
        }
END
);

        echo $CONF > "$DIR/configs/$ROLE.config.json"
        CONFIG="-hubConfig $DIR/configs/$ROLE.config.json"
    else
        CONFIG="-hubConfig $config"
    fi
fi

if [[ $ROLE = "standalone" ]]; then
    if [[ -z $PORT ]]; then
        PORT="4444"
    fi

    if [[ -z $CONFIG ]]; then
        CONF=$(cat <<-END
        {
            "host": "$ADDRESS",
            "port": $PORT,
            "role": "$ROLE",
            "debug": $DEBUG,
            "browserTimeout": 0,
            "timeout": 1800,
            "enablePassThrough": true,
            "capabilities": [
END
);

        check_chrome "CONF"
        check_firefox "CONF"
        check_opera "CONF"
        CONF=${CONF%?};
        CONF+="]}"
        echo $CONF > "$DIR/configs/$ROLE.config.json"
        CONFIG="-config $DIR/configs/$ROLE.config.json"
    else
        CONFIG="-config $config"
    fi
fi

# If jar is not defined find the newest selenium jar
if [[ -z $JAR ]];
then
    check_selenium "JAR"
fi

# Generate hub parameter based on HUB value
if [[ -z $HUB ]]; then
    HUB=""
else
    HUB="-hub $HUB"
fi

# Generate debug parameter based on DEBUG value
if [[ "$DEBUG" = "true" ]]; then
    DEBUG="-debug"
else
    DEBUG=""
fi

semver_version "$JAR" "SELENIUM_VERSION"
java -jar $JAR -role $ROLE -log $DIR/logs/$NAME-server-$SELENIUM_VERSION.log -host $ADDRESS -port $PORT $CONFIG $DEBUG $HUB
