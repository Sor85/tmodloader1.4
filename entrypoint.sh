#!/bin/bash

source ./entrypoint-functions.sh

pipe=/tmp/tmod.pipe

echo -e "[SYSTEM] Shutdown Message set to: $TMOD_SHUTDOWN_MESSAGE"
echo -e "[SYSTEM] Save Interval set to: $TMOD_AUTOSAVE_INTERVAL minutes"

configPath=/terraria-server/serverconfig.txt
workshopContentPath=/data/steamMods/steamapps/workshop/content/1281930
modUpdateStatePath=/data/steamMods/tmodloader-workshop-updates.state

# Check Config
if [[ "$TMOD_USECONFIGFILE" == "Yes" ]]; then
    if [ -e /terraria-server/customconfig.txt ]; then
        echo -e "[!!] The tModLoader server was set to load with a config file. It will be used instead of the environment variables."
    else
        echo -e "[!!] FATAL: The tModLoader server was set to launch with a config file, but it was not found. Please map the file to /terraria-server/customconfig.txt and launch the server again."
        sleep 5s
        exit 1
    fi
else
  ./prepare-config.sh
fi

set_mod_sources

# Trapped Shutdown, to cleanly shutdown
function shutdown () {
  inject "say $TMOD_SHUTDOWN_MESSAGE"
  sleep 3s
  inject "exit"
  tmuxPid=$(pgrep tmux)
  tmodPid=$(pgrep --oldest --parent $tmuxPid)
  while [ -e /proc/$tmodPid ]; do
    sleep .5
  done
  rm $pipe
}

# Download Mods
if test -z "${TMOD_AUTODOWNLOAD}" ; then
    echo -e "[SYSTEM] No mods to download. If you wish to download mods at runtime, please set the TMOD_AUTODOWNLOAD environment variable equal to a comma separated list of Mod Workshop IDs."
    echo -e "[SYSTEM] For more information, please see the Github README."
    sleep 5s
else
    modsToDownload=$(filter_download_mod_ids "$TMOD_AUTODOWNLOAD" "$modUpdateStatePath" "$workshopContentPath")

    if test -z "$modsToDownload" ; then
      echo -e "[SYSTEM] All specified mods are already up to date. Skipping SteamCMD download."
    else
      echo -e "[SYSTEM] Downloading missing or updated Mods specified in the TMOD_AUTODOWNLOAD Environment Variable. This may hand a while depending on the number of mods..."
      # Convert the Comma Separated list of Mod IDs to a list of SteamCMD commands and call SteamCMD to download them all.
      steamcmd +force_install_dir /data/steamMods +login anonymous +workshop_download_item 1281930 `echo -e $modsToDownload | sed 's/,/ +workshop_download_item 1281930 /g'` +quit
      if [ $? -eq 0 ]; then
        write_mod_update_state "$TMOD_AUTODOWNLOAD" "$modUpdateStatePath"
        echo -e "[SYSTEM] Finished downloading mods."
      else
        echo -e "[!!] An error occurred while attempting to download mods."
      fi
    fi
fi

# Enable Mods
if test -z "${TMOD_ENABLEDMODS}" ; then
    echo -e "[SYSTEM] The TMOD_ENABLEDMODS environment variable is not set. Defaulting to the mods specified in /data/tModLoader/Mods/enabled.json"
    echo -e "[SYSTEM] To change which mods are enabled, set the TMOD_ENABLEDMODS environment variable to a comma seperated list of mod Workshop IDs."
    echo -e "[SYSTEM] For more information, please see the Github README."
    sleep 5s
else
  enabledpath=/data/tModLoader/Mods/enabled.json
  modpath=$workshopContentPath
  rm -f $enabledpath
  mkdir -p /data/tModLoader/Mods
  touch $enabledpath

  echo -e "[SYSTEM] Enabling Mods specified in the TMOD_ENABLEDMODS Environment variable..."
  echo '[' >> $enabledpath
  # Convert the Comma separated list of Mod IDs to an iterable list. We use this to drill through the directories and get the internal names of the mods.
  echo -e $TMOD_ENABLEDMODS | tr "," "\n" | while read LINE
  do
    echo -e "[SYSTEM] Enabling $LINE..."

    if [ $? -ne 0 ]; then
      echo -e "[!!] Mod ID $LINE not found! Has it been downloaded?"
      continue
    fi
    modname=$(ls -1 $(ls -d $modpath/$LINE/*/|tail -n 1) | sed -e 's/\.tmod$//')
    if [ $? -ne 0 ]; then
      echo -e " [!!] An error occurred while attempting to load $LINE."
      continue
    fi
    # For each mod name that we resolve, write the internal name of it to the enabled.json file.
    echo "\"$modname\"," >> $enabledpath
    echo -e "[SYSTEM] Enabled $modname ($LINE) "
  done
    echo ']' >> $enabledpath
    echo -e "\n[SYSTEM] Finished loading mods."
fi

# Startup command
server="/terraria-server/LaunchUtils/ScriptCaller.sh -server -tmlsavedirectory \"/data/tModLoader\" -steamworkshopfolder \"/data/steamMods/steamapps/workshop\" -config \"$configPath\""

# Trap the shutdown
trap shutdown TERM INT
echo -e "tModLoader is launching with the following command:"
echo -e $server

# Check if the pipe exists already and remove it.
if [ -e "$pipe" ]; then
  rm $pipe
fi

# Create the tmux and pipe, so we can inject commands from 'docker exec [container id] inject [command]' on the host
sleep 5s
mkfifo $pipe
tmux new-session -d "$server | tee $pipe"

# Call the autosaver
/terraria-server/autosave.sh &

# Infinitely print the contents of the pipe, so the container still logs the Terraria Server.
cat $pipe &
wait ${!}
