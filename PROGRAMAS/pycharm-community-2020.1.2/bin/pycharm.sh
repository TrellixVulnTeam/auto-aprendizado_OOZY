#!/bin/sh
# ---------------------------------------------------------------------
# PyCharm startup script.
# ---------------------------------------------------------------------

message()
{
  TITLE="Cannot start PyCharm"
  if [ -n "$(command -v zenity)" ]; then
    zenity --error --title="$TITLE" --text="$1" --no-wrap
  elif [ -n "$(command -v kdialog)" ]; then
    kdialog --error "$1" --title "$TITLE"
  elif [ -n "$(command -v notify-send)" ]; then
    notify-send "ERROR: $TITLE" "$1"
  elif [ -n "$(command -v xmessage)" ]; then
    xmessage -center "ERROR: $TITLE: $1"
  else
    printf "ERROR: %s\n%s\n" "$TITLE" "$1"
  fi
}

UNAME=$(command -v uname)
GREP=$(command -v egrep)
CUT=$(command -v cut)
READLINK=$(command -v readlink)
XARGS=$(command -v xargs)
DIRNAME=$(command -v dirname)
MKTEMP=$(command -v mktemp)
RM=$(command -v rm)
CAT=$(command -v cat)
SED=$(command -v sed)

if [ -z "$UNAME" ] || [ -z "$GREP" ] || [ -z "$CUT" ] || [ -z "$DIRNAME" ] || [ -z "$MKTEMP" ] || [ -z "$RM" ] || [ -z "$CAT" ] || [ -z "$SED" ]; then
  message "Required tools are missing - check beginning of \"$0\" file for details."
  exit 1
fi

# shellcheck disable=SC2034
GREP_OPTIONS=''
OS_TYPE=$("$UNAME" -s)

# ---------------------------------------------------------------------
# Ensure $IDE_HOME points to the directory where the IDE is installed.
# ---------------------------------------------------------------------
SCRIPT_LOCATION="$0"
if [ -x "$READLINK" ]; then
  while [ -L "$SCRIPT_LOCATION" ]; do
    SCRIPT_LOCATION=$("$READLINK" -e "$SCRIPT_LOCATION")
  done
fi

cd "$("$DIRNAME" "$SCRIPT_LOCATION")" || exit 2
IDE_BIN_HOME=$(pwd)
IDE_HOME=$("$DIRNAME" "$IDE_BIN_HOME")
cd "${OLDPWD}" || exit 2

# ---------------------------------------------------------------------
# Locate a JDK installation directory command -v will be used to run the IDE.
# Try (in order): $PYCHARM_JDK, .../pycharm.jdk, .../jbr, .../jre64, $JDK_HOME, $JAVA_HOME, "java" in $PATH.
# ---------------------------------------------------------------------
# shellcheck disable=SC2154
if [ -n "$PYCHARM_JDK" ] && [ -x "$PYCHARM_JDK/bin/java" ]; then
  JDK="$PYCHARM_JDK"
fi

if [ -z "$JDK" ] && [ -s "${XDG_CONFIG_HOME:-$HOME/.config}/JetBrains/PyCharmCE2020.1/pycharm.jdk" ]; then
  USER_JRE=$("$CAT" "${XDG_CONFIG_HOME:-$HOME/.config}/JetBrains/PyCharmCE2020.1/pycharm.jdk")
  if [ ! -d "$USER_JRE" ]; then
    USER_JRE="$IDE_HOME/$USER_JRE"
  fi
  if [ -x "$USER_JRE/bin/java" ]; then
    JDK="$USER_JRE"
  fi
fi

if [ -z "$JDK" ] && [ "$OS_TYPE" = "Linux" ]; then
  OS_ARCH=$("$UNAME" -m)
  if [ "$OS_ARCH" = "x86_64" ] && [ -d "$IDE_HOME/jbr" ]; then
    JDK="$IDE_HOME/jbr"
  fi
  if [ -z "$JDK" ] && [ -d "$IDE_HOME/jbr-x86" ] && "$IDE_HOME/jbr-x86/bin/java" -version > /dev/null 2>&1 ; then
    JDK="$IDE_HOME/jbr-x86"
  fi
fi

# shellcheck disable=SC2153
if [ -z "$JDK" ] && [ -n "$JDK_HOME" ] && [ -x "$JDK_HOME/bin/java" ]; then
  JDK="$JDK_HOME"
fi

if [ -z "$JDK" ] && [ -n "$JAVA_HOME" ] && [ -x "$JAVA_HOME/bin/java" ]; then
  JDK="$JAVA_HOME"
fi

if [ -z "$JDK" ]; then
  JDK_PATH=$(command -v java)

  if [ -n "$JDK_PATH" ]; then
    if [ "$OS_TYPE" = "FreeBSD" ] || [ "$OS_TYPE" = "MidnightBSD" ]; then
      JAVA_LOCATION=$(JAVAVM_DRYRUN=yes java | "$GREP" '^JAVA_HOME' | "$CUT" -c11-)
      if [ -x "$JAVA_LOCATION/bin/java" ]; then
        JDK="$JAVA_LOCATION"
      fi
    elif [ "$OS_TYPE" = "SunOS" ]; then
      JAVA_LOCATION="/usr/jdk/latest"
      if [ -x "$JAVA_LOCATION/bin/java" ]; then
        JDK="$JAVA_LOCATION"
      fi
    elif [ "$OS_TYPE" = "Darwin" ]; then
      JAVA_LOCATION=$(/usr/libexec/java_home)
      if [ -x "$JAVA_LOCATION/bin/java" ]; then
        JDK="$JAVA_LOCATION"
      fi
    fi
  fi

  if [ -z "$JDK" ] && [ -n "$JDK_PATH" ] && [ -x "$READLINK" ] && [ -x "$XARGS" ]; then
    JAVA_LOCATION=$("$READLINK" -f "$JDK_PATH")
    case "$JAVA_LOCATION" in
      */jre/bin/java)
        JAVA_LOCATION=$(echo "$JAVA_LOCATION" | "$XARGS" "$DIRNAME" | "$XARGS" "$DIRNAME" | "$XARGS" "$DIRNAME")
        if [ ! -d "$JAVA_LOCATION/bin" ]; then
          JAVA_LOCATION="$JAVA_LOCATION/jre"
        fi
        ;;
      *)
        JAVA_LOCATION=$(echo "$JAVA_LOCATION" | "$XARGS" "$DIRNAME" | "$XARGS" "$DIRNAME")
        ;;
    esac
    if [ -x "$JAVA_LOCATION/bin/java" ]; then
      JDK="$JAVA_LOCATION"
    fi
  fi
fi

JAVA_BIN="$JDK/bin/java"
if [ -z "$JDK" ] || [ ! -x "$JAVA_BIN" ]; then
  X86_JRE_URL=""
  # shellcheck disable=SC2166
  if [ -n "$X86_JRE_URL" ] && [ ! -d "$IDE_HOME/jbr-x86" ] && [ "$OS_ARCH" = "i386" -o "$OS_ARCH" = "i686" ]; then
    message "To run PyCharm on a 32-bit system, please download 32-bit Java runtime from \"$X86_JRE_URL\" and unpack it into \"jbr-x86\" directory."
  else
    message "No JDK found. Please validate either PYCHARM_JDK, JDK_HOME or JAVA_HOME environment variable points to valid JDK installation."
  fi
  exit 1
fi

VERSION_LOG=$("$MKTEMP" -t java.version.log.XXXXXX)
JAVA_TOOL_OPTIONS='' "$JAVA_BIN" -version 2> "$VERSION_LOG"
"$GREP" "64-Bit|x86_64|amd64" "$VERSION_LOG" > /dev/null
BITS=$?
"$RM" -f "$VERSION_LOG"
test ${BITS} -eq 0 && BITS="64" || BITS=""

# ---------------------------------------------------------------------
# Collect JVM options and IDE properties.
# ---------------------------------------------------------------------
# shellcheck disable=SC2154
if [ -n "$PYCHARM_PROPERTIES" ]; then
  IDE_PROPERTIES_PROPERTY="-Didea.properties.file=$PYCHARM_PROPERTIES"
fi

VM_OPTIONS_FILE=""
# shellcheck disable=SC2154
if [ -n "$PYCHARM_VM_OPTIONS" ] && [ -r "$PYCHARM_VM_OPTIONS" ]; then
  # explicit
  VM_OPTIONS_FILE="$PYCHARM_VM_OPTIONS"
elif [ -r "$IDE_HOME.vmoptions" ]; then
  # Toolbox
  VM_OPTIONS_FILE="$IDE_HOME.vmoptions"
elif [ -r "${XDG_CONFIG_HOME:-$HOME/.config}/JetBrains/PyCharmCE2020.1/pycharm$BITS.vmoptions" ]; then
  # user-overridden
  VM_OPTIONS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/JetBrains/PyCharmCE2020.1/pycharm$BITS.vmoptions"
elif [ -r "$IDE_BIN_HOME/pycharm$BITS.vmoptions" ]; then
  # default, standard installation
  VM_OPTIONS_FILE="$IDE_BIN_HOME/pycharm$BITS.vmoptions"
else
  # default, universal package
  test "$OS_TYPE" = "Darwin" && OS_SPECIFIC="mac" || OS_SPECIFIC="linux"
  VM_OPTIONS_FILE="$IDE_BIN_HOME/$OS_SPECIFIC/pycharm$BITS.vmoptions"
fi

VM_OPTIONS=""
if [ -r "$VM_OPTIONS_FILE" ]; then
  VM_OPTIONS=$("$CAT" "$VM_OPTIONS_FILE" | "$GREP" -v "^#.*")
  if { echo "$VM_OPTIONS" | "$GREP" -q "agentlib:yjpagent" - ; }; then
    if [ "$OS_TYPE" = "Linux" ]; then
      VM_OPTIONS=$(echo "$VM_OPTIONS" | "$SED" -e "s|-agentlib:yjpagent\(-linux\)\?\([^=]*\)|-agentpath:$IDE_BIN_HOME/libyjpagent-linux\2.so|")
    else
      VM_OPTIONS=$(echo "$VM_OPTIONS" | "$SED" -e "s|-agentlib:yjpagent[^ ]*||")
    fi
  fi
else
  message "Cannot find VM options file"
fi

CLASSPATH="$IDE_HOME/lib/bootstrap.jar"
CLASSPATH="$CLASSPATH:$IDE_HOME/lib/extensions.jar"
CLASSPATH="$CLASSPATH:$IDE_HOME/lib/util.jar"
CLASSPATH="$CLASSPATH:$IDE_HOME/lib/jdom.jar"
CLASSPATH="$CLASSPATH:$IDE_HOME/lib/log4j.jar"
CLASSPATH="$CLASSPATH:$IDE_HOME/lib/trove4j.jar"
CLASSPATH="$CLASSPATH:$IDE_HOME/lib/jna.jar"
# shellcheck disable=SC2154
if [ -n "$PYCHARM_CLASSPATH" ]; then
  CLASSPATH="$CLASSPATH:$PYCHARM_CLASSPATH"
fi

# ---------------------------------------------------------------------
# Run the IDE.
# ---------------------------------------------------------------------
IFS="$(printf '\n\t')"
# shellcheck disable=SC2086
"$JAVA_BIN" \
  -classpath "$CLASSPATH" \
  ${VM_OPTIONS} \
  "-XX:ErrorFile=$HOME/java_error_in_PYCHARM_%p.log" \
  "-XX:HeapDumpPath=$HOME/java_error_in_PYCHARM.hprof" \
  -Didea.paths.selector=PyCharmCE2020.1 \
  "-Djb.vmOptionsFile=$VM_OPTIONS_FILE" \
  ${IDE_PROPERTIES_PROPERTY} \
  -Didea.platform.prefix=PyCharmCore \
  com.intellij.idea.Main \
  "$@"
