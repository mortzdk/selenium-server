#! /bin/bash
#
# server.sh
#
# Version: 0.1
#
# Script for starting selenium server node, hub, or standalone on Linux, MacOS, 
# and Window (Cygwin).
#
# The script requires that the following programs are installed:
# * arch
# * java
# * wget
# * unzip
# * tar
# * sed
# * jq
#
# For CygWin it is moreover required that powershell is installed.
#
# Copyright (C) 2019 Morten Houmøller Nygaard <mortzdk@gmail.com>
#
# Distributed under terms of the MIT license.

# DEFAULT VALUES
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
DEBUG="false"
ADDRESS="0.0.0.0"
JAVA_ARGS=""
ROLE="standalone"
MAXINSTANCES=5
NAME=""

# Get platform script is running on
unameOut="$(uname -s)"
case "${unameOut}" in
    Linux*)
        PLATFORM="linux";
        PLATFORM_NAME="linux";
        EXT=""
        ;;
    Darwin*)
        PLATFORM="mac";
        PLATFORM_NAME="mac";
        EXT=""
        ;;
    CYGWIN*)
        PLATFORM="win";
        PLATFORM_NAME="windows";
        EXT=".exe";
        DIR="."
        ;;
    *)          
        echo "ERROR: Unsupported platform '$unameOut'." >&2;
        exit 1
esac

archOut="$(arch)"
case "${archOut}" in
    i686*)
        ARCH="32"
        ;;
    x86_64*)
        ARCH="64"
        ;;
    *)
        echo "ERROR: Unsupported architecture '$archOut'." >&2;
        exit 1
esac

# Show how to use server script
function show_info() {
    echo -e "./server.sh\n\t-i Shows the information about the arguments available for the server\n\t-d Enable debug mode\n\t-n {NAME} A name for the application server\n\t-r {ROLE} Which role the server should have. Valid arguments are 'standalone', 'node', 'hub'.\n\t-h {HUB_HOST} The address to the hub host\n\t-j {JAR_PATH} The path to a selenium server jar. If none is present, the newest in the jars folder will be used.\n\t-a {ADDRESS} The address for which the server should run. Default to 0.0.0.0.\n\t-p {PORT} The port that the server should run on. Default 4444 for standalone and hub, and 5555 for node\n\t-m {MAXINSTANCES} The number of instances of each of the drivers\n\t-D {JAVA_ARGS} Arguments to supply to the jar\n\t-c {CONFIG_PATH} The path to a selenium config json file. If none is present, a config file will be generated based on the environment.";
    exit 1
}

# Parse options to script
while getopts r:a:j:p:c:h:m:D:id option
do
case "${option}"
in
a) 
    ADDRESS=${OPTARG}
    ;;
i) 
    show_info
    ;;
j) 
    JAR=${OPTARG}
    ;;
p) 
    PORT=${OPTARG}
    ;;
c) 
    CONFIG=${OPTARG}
    ;;
h) 
    HUB=${OPTARG}
    ;;
r) 
    ROLE=${OPTARG}
    ;;
d) 
    DEBUG="true"
    ;;
D) 
    JAVA_ARGS=${OPTARG}
    ;;
m)
    if [[ ${OPTARG} =~ ^[0-9]+$ ]] ; then
        MAXINSTANCES=${OPTARG}
    fi
    ;;
n)
    NAME=${OPTARG}
    ;;
esac
done

# Check role is valid
case $ROLE in
    standalone)
        ;;
    node)
        ;;
    hub)
        ;;
    *)
        show_info
        ;;
esac

# Generate application name
if [[ -z $NAME ]];
then
    NAME="selenium-$ROLE"
else
    NAME="selenium-$ROLE-$NAME"
fi

# Function that checks whether command is available and installed
function is_installed()
{
    if ! [ -x "$(command -v $1)" ]; then
        echo "☒ $1"
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

    echo "Using selenium version $SELENIUM_VERSION"
    
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

    if [[ $PLATFORM = "win" ]]
    then
        CHROME_STRING=$(echo "\n" | powershell.exe -command "Get-ItemProperty HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\* | % { Get-ItemProperty \$_.PsPath } | Select DisplayName, DisplayVersion, InstallLocation | ForEach-Object { \$_.DisplayName + ';' + \$_.DisplayVersion + ';' + \$_.InstallLocation }" | grep -i "google chrome")
        if [[ -z "${CHROME_STRING// }" ]]; then
            return
        fi

        IFS=';' read -ra DATA <<< "$CHROME_STRING"
        CHROME_STRING=${DATA[1]}
        CHROME_PATH="$(echo ${DATA[2]} | sed $'s/\r//')\\chrome.exe"
    elif [[ -x "$(command -v 'google-chrome')" ]]
    then
        CHROME_PATH=$(which google-chrome)
        CHROME_STRING=$($CHROME_PATH --version)
    elif [[ -x "$(command -v 'google-chrome-stable')" ]]
    then
        CHROME_PATH=$(which google-chrome-stable)
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
    echo "Using chromedriver version: $CD_VERSION"
    echo "For chrome version: $CHROME_VERSION"
    if [ ! -f "$DIR/drivers/chromedriver-$CD_VERSION" ]; then
        wget --no-verbose -O "/tmp/chromedriver_${PLATFORM}${ARCH}.zip" "https://chromedriver.storage.googleapis.com/$CD_VERSION/chromedriver_${PLATFORM}${ARCH}.zip"
        unzip "/tmp/chromedriver_${PLATFORM}${ARCH}.zip" -d "$DIR/drivers"
        rm "/tmp/chromedriver_${PLATFORM}${ARCH}.zip"
        mv "$DIR/drivers/chromedriver$EXT" "$DIR/drivers/chromedriver-$CD_VERSION$EXT"
        chmod 755 "$DIR/drivers/chromedriver-$CD_VERSION$EXT"
    fi

    local ESCAPED_CHROME_PATH=$(jq -aR . <<< "$CHROME_PATH")
    local cap=$(cat <<-END
    {
        \"version\": \"$CHROME_VERSION\",
        \"browserName\": \"chrome\",
        \"platformName\": \"$PLATFORM_NAME\",
        \"maxInstances\": $MAXINSTANCES,
        \"seleniumProtocol\": \"WebDriver\",
        \"applicationName\": \"$NAME-chrome\",
        \"chromeOptions\": {
            \"binary\" : $(echo $ESCAPED_CHROME_PATH | sed -e 's/\\/\\\\/g'| sed -e 's/"/\\"/g')
        }
    },
END
)
    eval "$1+=\"$cap\""
    eval "$2+=\"-Dwebdriver.chrome.driver=$DIR/drivers/chromedriver-$CD_VERSION$EXT -Dwebdriver.chrome.logfile=$DIR/logs/chromedriver.log -Dwebdriver.chrome.verboseLogging=true \""
}

# Check if firefox is installed, download corresponding driver and generate
# capabilities.
function check_firefox {
    local FIREFOX_STRING=""
    local COMP_EXT="tar.gz"

    if [[ $PLATFORM = "win" ]]
    then
        FIREFOX_STRING=$(echo "\n" | powershell.exe -command "Get-ItemProperty HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\* | % { Get-ItemProperty \$_.PsPath } | Select DisplayName, DisplayVersion, InstallLocation | ForEach-Object { \$_.DisplayName + ';' + \$_.DisplayVersion + ';' + \$_.InstallLocation }" | grep -i "mozilla firefox")
        if [[ -z "${FIREFOX_STRING// }" ]]; then
            return
        fi

        IFS=';' read -ra DATA <<< "$FIREFOX_STRING"
        FIREFOX_STRING=${DATA[1]}
        FIREFOX_PATH="$(echo ${DATA[2]} | sed $'s/\r//')"
        FIREFOX_PATH=$(echo $FIREFOX_PATH | sed -e 's/\\/\//g' | sed -e 's/C:/\/cygdrive\/c/g' | sed -e 's/ /\\ /g' | sed -e 's/(/\\(/g' | sed -e 's/)/\\)/g')
        export PATH=$PATH:$FIREFOX_PATH
        COMP_EXT="zip"
    elif [[ -x "$(command -v 'firefox')" ]]
    then
        FIREFOX_PATH=$(which firefox)
        FIREFOX_STRING=`$FIREFOX_PATH --version`
    else
        return
    fi

    semver_version "$FIREFOX_STRING" "FIREFOX_VERSION"

    semver_version `wget -qO- "https://api.github.com/repos/mozilla/geckodriver/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'` "GK_VERSION"

    echo "Using GeckoDriver version: "$GK_VERSION
    echo "For Firefox version: $FIREFOX_VERSION"

    if [ ! -f "$DIR/drivers/geckodriver-$GK_VERSION$EXT" ]; then
        wget --no-verbose -O "/tmp/geckodriver.$COMP_EXT" "https://github.com/mozilla/geckodriver/releases/download/v$GK_VERSION/geckodriver-v$GK_VERSION-${PLATFORM}${ARCH}.$COMP_EXT"
        if [[ "$COMP_EXT" = "zip" ]]; then
            unzip "/tmp/geckodriver.$COMP_EXT" -d "$DIR/drivers"
            rm "/tmp/geckodriver.$COMP_EXT"
        else
            tar -C "$DIR/drivers" -zxf "/tmp/geckodriver.$COMP_EXT"
            rm "/tmp/geckodriver.$COMP_EXT"
        fi
        mv "$DIR/drivers/geckodriver$EXT" "$DIR/drivers/geckodriver-$GK_VERSION$EXT"
        chmod 755 "$DIR/drivers/geckodriver-$GK_VERSION$EXT"
    fi

    local cap=$(cat <<-END
    {
        \"marionette\": true,
        \"version\": \"$FIREFOX_VERSION\",
        \"browserName\": \"firefox\",
        \"platformName\": \"$PLATFORM_NAME\",
        \"maxInstances\": $MAXINSTANCES,
        \"seleniumProtocol\": \"WebDriver\",
        \"moz:firefoxOptions\" : {
            \"log\": {
                \"level\": \"trace\"
            }
        },
        \"applicationName\": \"$NAME-firefox\"
    },
END
)

    eval "$1+=\"$cap\""
    eval "$2+=\"-Dwebdriver.gecko.driver=$DIR/drivers/geckodriver-$GK_VERSION$EXT -Dwebdriver.firefox.logfile=$DIR/logs/geckodriver.log \""

    if [[ $PLATFORM != "win" ]]
    then
        eval "$2+=\"-Dwebdriver.firefox.bin='$FIREFOX_PATH' \""
    fi
}

# Check if opera is installed, download corresponding driver and generate
# capabilities.
function check_opera {
    if [[ $PLATFORM = "win" ]]
    then
        local OPATH=$(echo $USERPROFILE | sed -e 's/\\/\//g' | sed -e 's/C:/\/cygdrive\/c/g' | sed -e 's/ /\\ /g' | sed -e 's/(/\\(/g' | sed -e 's/)/\\)/g')
        if [[ -d "/cygdrive/c/Program\ Files/Opera" ]]; then
            OPERA_PATH="/cygdrive/c/Program\ Files/Opera"
        elif [[ -d "$OPATH/AppData/Local/Programs/Opera" ]]; then
            OPERA_PATH="$OPATH/AppData/Local/Programs/Opera"
        else
            return
        fi

        if [[ -f "$OPERA_PATH/opera.exe" ]]; then
            OPERA_PATH+="/opera.exe"
            OPERA_VERSION=$($OPERA_PATH --version)
        else
            while IFS='' read -r line || [ -n "$line" ]; do
                [ -z "$line" ] && continue
                semver_version $line "OPERA_VERSION"
                if ! [[ -z $OPERA_VERSION ]]; then
                    OPERA_PATH+="/$OPERA_VERSION/opera.exe" 
                    break 
                fi
            done < <(find $OPERA_PATH -maxdepth 1 -type d -printf '%f\n')

            if [[ -z $OPERA_VERSION ]]; then
                return
            fi
        fi
    elif [[ -x "$(command -v 'opera')" ]]
    then
        OPERA_PATH=$(which opera)
        OPERA_VERSION="$($OPERA_PATH --version)"
    else
        return
    fi

    compare_versions "$OPERA_VERSION" "25"
    if [[ "$?" = "1" ]];
    then
        semver_version `wget -qO- "https://api.github.com/repos/operasoftware/operachromiumdriver/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'` "OD_VERSION"

        echo "Using OperaChromiumDriver version: "$OD_VERSION
        echo "For Opera version: $OPERA_VERSION"

        if [ ! -f "$DIR/drivers/operachromiumdriver-$OD_VERSION$EXT" ]; then
            wget --no-verbose -O "/tmp/operachromiumdriver_${PLATFORM}${ARCH}.zip" "https://github.com/operasoftware/operachromiumdriver/releases/download/v.$OD_VERSION/operadriver_${PLATFORM}${ARCH}.zip"
            unzip "/tmp/operachromiumdriver_${PLATFORM}${ARCH}.zip" -d "/tmp/operachromiumdriver"
            rm "/tmp/operachromiumdriver_${PLATFORM}${ARCH}.zip"
            mv "/tmp/operachromiumdriver/operadriver_${PLATFORM}${ARCH}/operadriver$EXT" "$DIR/drivers/operachromiumdriver-$OD_VERSION$EXT"
            chmod 755 "$DIR/drivers/operachromiumdriver-$OD_VERSION$EXT"
            rm -rf "/tmp/operachromiumdriver"
        fi
    else
        return
    fi

    local ESCAPED_OPERA_PATH=$(jq -aR . <<< "$OPERA_PATH")
    local cap=$(cat <<-END
    {
        \"version\": \"$OPERA_VERSION\",
        \"browserName\": \"opera\",
        \"platformName\": \"$PLATFORM_NAME\",
        \"maxInstances\": $MAXINSTANCES,
        \"seleniumProtocol\": \"WebDriver\",
        \"applicationName\": \"$NAME-opera\",
        \"operaOptions\": {
            \"binary\" : $(echo $ESCAPED_OPERA_PATH | sed -e 's/\\/\\\\/g'| sed -e 's/"/\\"/g')
        }
    },
END
)

    eval "$1+=\"$cap\""
    eval "$2+=\"-Dwebdriver.opera.driver=$DIR/drivers/operachromiumdriver-$OD_VERSION$EXT -Dwebdriver.opera.logfile=$DIR/logs/operachromiumdriver.log -Dwebdriver.opera.verboseLogging=true \""
}

#function check_safari {
#    if [[ -x "$(command -v 'safari')" ]]
#    then
#        SAFARI_PATH=$(which safari)
#        SAFARI_STRING="$($SAFARI_PATH --version)"
#
#        semver_version "$SAFARI_STRING" "SAFARI_VERSION_STRING"
#        compare_versions "$SAFARI_VERSION_STRING" "10"
#        
#        if [[ "$?" = "1" ]] || [[ "$?" = "0" ]]; then
#            if ! [[ -f "/usr/bin/safaridriver" ]]; then
#                return
#            fi
#            echo "Using /usr/bin/safaridriver"
#            echo "For Safari version: $SAFARI_VERSION_STRING"
#            /usr/bin/safaridriver
#        else
#            #TODO Old safari driver
#            return
#        fi
#    else
#        return
#    fi
#
#    local cap=$(cat <<-END
#    {
#        \"version\": \"$OPERA_VERSION_STRING\",
#        \"browserName\": \"safari\",
#        \"platformName\": \"$PLATFORM_NAME\",
#        \"maxInstances\": $MAXINSTANCES,
#        \"seleniumProtocol\": \"WebDriver\",
#        \"applicationName\": \"$NAME-safari\"
#    },
#END
#)
#
#    eval "$1+=\"$cap\""
#    eval "$2+=\"-Dwebdriver.safari.driver=/usr/bin/safaridriver \""
#}

function check_ie {
    local IE_STRING=""
    local IE_ARCH=""
    if [[ $PLATFORM = "win" ]]
    then
        IE_STRING=`echo "\n" | powershell.exe -command "(Get-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Internet Explorer').SvcVersion"`
        if [[ -z "${IE_STRING// }" ]]; then
            IE_STRING=`echo "\n" | powershell.exe -command "(Get-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Internet Explorer').Version"`
            if [[ -z "${IE_STRING// }" ]]; then
                return
            fi
        fi
    else
        return
    fi

    semver_version "$IE_STRING" "IE_VERSION_STRING"

    wget -q --no-verbose -O /tmp/SELENIUM_RELEASE "https://selenium-release.storage.googleapis.com/"
    if [[ "$ARCH" == "32" ]]; then
        IE_ARCH="Win32"
    else
        IE_ARCH="x64"
    fi
    local versions=`cat /tmp/SELENIUM_RELEASE | grep -Po "IEDriverServer_${IE_ARCH}_[\d+][\.\d+]*zip"`
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

    semver_version "$current_version" "ID_VERSION"

    echo "Using iedriver version $ID_VERSION"
    echo "For Internet Explore version: $IE_VERSION_STRING"

    if ! [[ -f "$DIR/drivers/iedriver-$ID_VERSION.exe" ]]; then
        wget --no-verbose -O "/tmp/IEDriverServer_${IE_ARCH}_$ID_VERSION.zip" "https://selenium-release.storage.googleapis.com/$MAJOR.$MINOR/IEDriverServer_${IE_ARCH}_$ID_VERSION.zip"
        unzip "/tmp/IEDriverServer_${IE_ARCH}_$ID_VERSION.zip" -d "$DIR/drivers"
        rm "/tmp/IEDriverServer_${IE_ARCH}_$ID_VERSION.zip"
        mv "$DIR/drivers/IEDriverServer.exe" "$DIR/drivers/iedriver-$ID_VERSION.exe"
        chmod 755 "$DIR/drivers/iedriver-$ID_VERSION.exe"
    fi

    local cap=$(cat <<-END
    {
        \"version\": \"$IE_VERSION_STRING\",
        \"browserName\": \"internet explorer\",
        \"platformName\": \"$PLATFORM_NAME\",
        \"maxInstances\": $MAXINSTANCES,
        \"seleniumProtocol\": \"WebDriver\",
        \"applicationName\": \"$NAME-ie\"
    },
END
)

    eval "$1+=\"$cap\""
    eval "$2+=\"-Dwebdriver.ie.driver=$DIR/drivers/iedriver-$ID_VERSION.exe -Dwebdriver.ie.driver.logfile=$DIR/logs/iedriver.log -Dwebdriver.ie.driver.loglevel=TRACE \""
}

function check_edge {
    if [[ $PLATFORM = "win" ]]
    then
        EDGE_STRING=`echo "\n" | powershell.exe -command "Get-AppxPackage -Name Microsoft.MicrosoftEdge | Foreach Version"`
        if [[ -z "${EDGE_STRING// }" ]]; then
            EDGE_STRING=`echo "\n" | powershell.exe -command "Get-AppxPackage -Name *Edge* | Foreach Version"`
            if [[ -z "${IE_STRING// }" ]]; then
                EDGE_STRING=`echo "\n" | powershell.exe -command "Get-AppxPackage -Name *Spartan* | Foreach Version"`
                if [[ -z "${IE_STRING// }" ]]; then
                    return
                fi
            fi
        fi
    else
        return
    fi

    semver_version "$EDGE_STRING" "EDGE_VERSION"

    # Determine EdgeHTML version based on edge version
    # https://en.wikipedia.org/wiki/Microsoft_Edge#EdgeHTML_(2014%E2%80%932019)_2
    compare_versions "$EDGE_VERSION" "44"
    if [[ "$?" = "1" ]] || [[ "$?" = "0" ]];
    then
        # 18
        EDGE_HTML_VERSION='18.17763'
    else
        compare_versions "$EDGE_VERSION" "42"
        if [[ "$?" = "1" ]] || [[ "$?" = "0" ]]; then
            # 17
            EDGE_HTML_VERSION='17.17134'
        else
            compare_versions "$EDGE_VERSION" "41"
            if [[ "$?" = "1" ]] || [[ "$?" = "0" ]];
            then
                # 16
                EDGE_HTML_VERSION='16.16299'
            else
                compare_versions "$EDGE_VERSION" "39.14942"
                if [[ "$?" = "1" ]] || [[ "$?" = "0" ]];
                then
                    # 15
                    EDGE_HTML_VERSION='15.15063'
                else
                    compare_versions "$EDGE_VERSION" "31"
                    if [[ "$?" = "1" ]] || [[ "$?" = "0" ]];
                    then
                        # 14
                        EDGE_HTML_VERSION='14.14393'
                    else
                        compare_versions "$EDGE_VERSION" "21"
                        if [[ "$?" = "1" ]] || [[ "$?" = "0" ]];
                        then
                            # 13
                            EDGE_HTML_VERSION='13.10586'
                        else
                            # 12
                            EDGE_HTML_VERSION='12.10240'
                        fi
                    fi
                fi
            fi
        fi
    fi

    if [[ -z "$EDGE_HTML_VERSION" ]]; then
        return
    fi

    echo "Using edgedriver version $EDGE_HTML_VERSION"
    echo "For Microsoft Edge version: $EDGE_VERSION"

    compare_versions "$EDGE_HTML_VERSION" "18"
    if ! [[ "$?" = 1 ]]; then
        if ! [[ -f "$DIR/drivers/edgedriver-$EDGE_HTML_VERSION.exe" ]]; then
            # Get minor version of driver 
            semver_version "$EDGE_HTML_VERSION" "EDGE_HTML_VERSION"
            if [[ -z "$MINOR" ]]; then
                return
            fi

            local DRIVERS=$(wget -qO- https://developer.microsoft.com/en-us/microsoft-edge/tools/webdriver/)
            local LINK=$(echo $DRIVERS | sed -n "s/.*href=\"\([^\"]*\)[^>]*>Release $MINOR<\/a>.*/\1/p")
            if [[ -z "$LINK" ]]; then
                return
            fi

            # Download driver
            wget --no-verbose -O "$DIR/drivers/edgedriver-$EDGE_HTML_VERSION.exe" $LINK
            chmod 755 "$DIR/drivers/edgedriver-$EDGE_HTML_VERSION.exe"
        fi

        eval "$2+=\"-Dwebdriver.edge.driver=$DIR/drivers/edgedriver-$EDGE_HTML_VERSION.exe \""
    fi

    local cap=$(cat <<-END
    {
        \"edgeHtmlVersion\": \"$EDGE_HTML_VERSION\",
        \"version\": \"$EDGE_VERSION\",
        \"browserName\": \"edge\",
        \"platformName\": \"$PLATFORM_NAME\",
        \"maxInstances\": $MAXINSTANCES,
        \"seleniumProtocol\": \"WebDriver\",
        \"applicationName\": \"$NAME-edge\"
    },
END
)

    eval "$1+=\"$cap\""
}

echo "========================== Checking Required Programs =========================="

is_installed "arch"
echo "☑ arch"
is_installed "java"
echo "☑ java"
is_installed "wget"
echo "☑ wget"
is_installed "unzip"
echo "☑ unzip"
is_installed "tar"
echo "☑ tar"
is_installed "sed"
echo "☑ sed"
is_installed "jq"
echo "☑ jq"


# Generate nodeConfig parameter
if [[ $ROLE = "node" ]]; then
    echo "========================== Generating configurations =========================="

    if [[ -z "$PORT" ]]; then
        PORT="5555"
    fi

    if [[ -z "$CONFIG" ]]; then
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
            "servlets" : [],
            "withoutServlets": [],
            "custom": {},
            "debug": $DEBUG,
            "capabilities": [
END
);

        check_chrome "CONF" "JAVA_ARGS"
        check_firefox "CONF" "JAVA_ARGS"
        check_opera "CONF" "JAVA_ARGS"
        #check_safari "CONF" "JAVA_ARGS"
        check_ie "CONF" "JAVA_ARGS"
        check_edge "CONF" "JAVA_ARGS"

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
    if [[ -z "$PORT" ]]; then
        PORT="4444"
    fi

    if [[ -z "$CONFIG" ]]; then
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

# Generate standalone config parameter
if [[ $ROLE = "standalone" ]]; then
    echo "========================== Generating configurations =========================="

    if [[ -z "$PORT" ]]; then
        PORT="4444"
    fi

    if [[ -z "$CONFIG" ]]; then
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

        check_chrome "CONF" "JAVA_ARGS"
        check_firefox "CONF" "JAVA_ARGS"
        check_opera "CONF" "JAVA_ARGS"
        #check_safari "CONF" "JAVA_ARGS"
        check_ie "CONF" "JAVA_ARGS"
        check_edge "CONF" "JAVA_ARGS"

        CONF=${CONF%?};
        CONF+="]}"
        echo $CONF > "$DIR/configs/$ROLE.config.json"
        CONFIG="-config $DIR/configs/$ROLE.config.json"
    else
        CONFIG="-config $config"
    fi
fi

echo "========================== Checking Selenium JAR =========================="

# If jar is not defined find the newest selenium jar
if [[ -z "$JAR" ]];
then
    check_selenium "JAR"
fi

# Generate hub parameter based on HUB value
if [[ -z "$HUB" ]]; then
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

echo "========================== Running Command: =========================="
echo java $JAVA_ARGS-jar "$JAR" -role "$ROLE" -log "$DIR/logs/$NAME-server-$SELENIUM_VERSION.log" -host "$ADDRESS" -port "$PORT" $CONFIG $DEBUG $HUB

echo "========================== Server type: $ROLE =========================="
semver_version "$JAR" "SELENIUM_VERSION"
java $JAVA_ARGS-jar "$JAR" -role "$ROLE" -log "$DIR/logs/$NAME-server-$SELENIUM_VERSION.log" -host "$ADDRESS" -port "$PORT" $CONFIG $DEBUG $HUB
