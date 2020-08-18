#!/bin/bash
#
# A very simple BASH script to take an input video and split it down into Segments 
# before creating an M3U8 Playlist, allowing the file to be served using HLS
#
#

######################################################################################
#
# Copyright (c) 2013, Ben Tasker
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:
# 
#   Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
# 
#   Redistributions in binary form must reproduce the above copyright notice, this
#   list of conditions and the following disclaimer in the documentation and/or
#   other materials provided with the distribution.
# 
#   Neither the name of Ben Tasker nor the names of his
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
# ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# 
######################################################################################

# Introduced in HLS-36 to allow tracking of issues
HLS_SC_VERSION="1.0"

args=()

if [ -n "${FFMPEG_PROXY:-}" ] 
then
    args+=( -http_proxy "$FFMPEG_PROXY" )
fi

if [ -n "${FFMPEG_USER_AGENT:-}" ] 
then
    args+=( -user_agent "$FFMPEG_USER_AGENT" )
fi

if [ -n "${FFMPEG_HEADERS:-}" ] 
then
    printf -v headers_command '%b' "$FFMPEG_HEADERS"
    args+=( -headers "$headers_command" )
fi

if [ -n "${FFMPEG_COOKIES:-}" ] 
then
    args+=( -cookies "$FFMPEG_COOKIES" )
fi

# Basic config
OUTPUT_DIRECTORY=${OUTPUT_DIRECTORY:-'./output'}

# Change this if you want to specify a path to use a specific version of FFMPeg
FFMPEG=${FFMPEG:-'ffmpeg'}

# Number of threads which will be used for transcoding. With newer FFMPEGs and x264
# encoders "0" means "optimal". This is normally the number of CPU cores.
NUMTHREADS=${NUMTHREADS:-"0"}

# Video codec for the output video. Will be used as an value for the -vcodec argument
VIDEO_CODEC=${VIDEO_CODEC:-"libx264"}

# Audio codec for the output video. Will be used as an value for the -acodec argument
AUDIO_CODEC=${AUDIO_CODEC:-"aac"}

# Additional flags for ffmpeg
FFMPEG_FLAGS=${FFMPEG_FLAGS:-""}
FFMPEG_INPUT_FLAGS=${FFMPEG_INPUT_FLAGS:-""}

# If the input is a live stream (i.e. linear video) this should be 1
LIVE_STREAM=${LIVE_STREAM:-0}

# Video bitrates to use in output (comma seperated list if you want to create an adaptive stream.)
# leave null to use the input bitrate
OP_BITRATES=${OP_BITRATES:-''}

# Determines whether the processing for adaptive streams should run sequentially or not
NO_FORK=${NO_FORK:-0}

# Path Prefix (Not incl. Key)
PATH_PREFIX=${PATH_PREFIX:-''}

# Key Path Prefix
KEY_PREFIX=${KEY_PREFIX:-''}

# Lets put our functions here


## Output the script's CLI Usage
#
#
function print_usage(){

cat << EOM
HTTP Live Stream Creator
Version 1

Copyright (C) 2013 B Tasker, D Atanasov
Released under BSD 3 Clause License
See LICENSE


Usage: HLS-Stream-Creator.sh -[CeflnS2] [-c segmentcount] -i [inputfile] -s [segmentlength(seconds)] -o [outputdir] -b [bitrates]


    Mandatory Arguments:

	-i [file]	Input file
	-s [s]		Segment length (seconds)

    Optional Arguments:

	-b [bitrates]	Output video Bitrates in kb/s (comma seperated list for adaptive streams)
	-c [count]	Number of segments to include in playlist (live streams only) - 0 is no limit
	-k [prefix]	String to prepend to Key path when encrpytion is used (e.g. https://mykeyserver.com/)
	-K [Name]	Name of file for decryption key (will have .key appended)
	-o [directory]	Output directory (default: ./output)
	-p [name]	Playlist filename prefix
	-q [quality]	Change encoding to CFR with [quality]
	-t [name]	Segment filename prefix
	-u [prefix]	Prefix to prepend to segment and manifest paths
	-C		Use constant bitrate as opposed to variable bitrate
	-e      	Encrypt the HLS segments (a key will be generated automatically)
	-f		Foreground encoding only (adaptive non-live streams only)
	-h              Print this help
	-l		Input is a live stream
        -n              Ignore audio track in input file
	-S		Name of a subdirectory to put segments into
	-2		Use two-pass encoding



Deprecated Legacy usage:
	HLS-Stream-Creator.sh inputfile segmentlength(seconds) [outputdir='./output']

EOM

exit

}


function createStream(){
# For VoD and single bitrate streams the variables we need will exist in Global scope.
# for live adaptive streams though, that won't be the case, so we need to take them as arguments
# Some are global though, so we'll leave those as is

playlist_name="$1"
output_name="$2"
bitrate="$3"
infile="$4"
failfile="$5"

# Resolution comes from global $resolution
#
# See HLS-27
#
# I don't like this use of $resolution when it's not local, but there was already a use 
# of non-local $br in here so I'll fix this later


local PASSVAR=
if $TWOPASS; then
	local LOGFILE="$OUTPUT_DIRECTORY/bitrate$br"
	PASSVAR="-passlogfile \"$LOGFILE\" -pass 2"

	$FFMPEG ${args[@]+"${args[@]}"} \
        -i "$infile" \
		-pass 1 \
		-passlogfile "$LOGFILE" \
		-an \
		-vcodec libx264 \
		-f mpegts \
		$bitrate \
		$resolution \
		$FFMPEG_ADDITIONAL \
		-loglevel error -y \
		/dev/null

        ext=$?
        if [ "$ext" != "0" ] && [ "$failfile"  != "" ]
        then
            echo $ext > $failfile
        fi


fi

$FFMPEG ${args[@]+"${args[@]}"} \
    $FFMPEG_INPUT_FLAGS \
    -i "$infile" \
    $PASSVAR \
    -y \
    -vcodec "$VIDEO_CODEC" \
    -acodec "$AUDIO_CODEC" \
    -threads "$NUMTHREADS" \
    -map 0 \
    -flags \
    -global_header \
    -f segment \
    -segment_list "$playlist_name" \
    -segment_time "$SEGLENGTH" \
    -segment_format mpeg_ts \
    $resolution \
    $bitrate \
    $FFMPEG_ADDITIONAL \
    $FFMPEG_FLAGS \
    "$OUTPUT_DIRECTORY/$output_name"

ext=$?
if [ "$ext" != "0" ] && [ "$failfile"  != "" ]
then
    echo $ext > $failfile
fi
    
    
}


function createVariantPlaylist(){
playlist_name="$1"
echo "#EXTM3U" > "$playlist_name"
}


function appendVariantPlaylistentry(){
playlist_name=$1
playlist_path=$2
bw_statement=$3
m3u8_resolution=''

if [[ "$bw_statement" == *"-"* ]]
then
    m3u8_resolution=",RESOLUTION=$(echo "$bw_statement" | cut -d- -f2)"
    bw_statement=$(echo "$bw_statement" | cut -d- -f1) 
fi

playlist_bw=$(( $bw_statement * 1000 )) # bits not bytes :)

cat << EOM >> "$playlist_name"
#EXT-X-STREAM-INF:BANDWIDTH=$playlist_bw$m3u8_resolution
$PATH_PREFIX$playlist_path
EOM

}


function awaitCompletion(){
# Monitor the encoding pids for their completion status
while [ ${#PIDS[@]} -ne 0 ]; do
    # Calculate the length of the array
    pid_length=$((${#PIDS[@]} - 1))

    # Check each PID in the array
    for i in `seq 0 $pid_length`
    do
	  # Test whether the pid is still active
	  if ! kill -0 ${PIDS[$i]} 2> /dev/null
	  then
	  
                if [ -f "$TMPDIR/bw-${BITRATE_PROCESSES[$i]}.$MYPID.failfile" ]
                then
                    echo "Error: FFMPEG process for bitrate exited ${BITRATE_PROCESSES[$i]} with status code `cat $TMPDIR/bw-${BITRATE_PROCESSES[$i]}.$MYPID.failfile`"
                    echo "Killing other processes"
                    for sub in `seq 0 $pid_length`
                    do
                        # We use pkill here because a simple kill will kill the shell process but leave ffmpeg active
                        pkill -9 -P ${PIDS[$sub]} 2> /dev/null
                    done
                    
                    rm -f "$TMPDIR/bw-*.$MYPID.failfile"
                    exit 1
                fi
	  
		echo "Encoding for bitrate ${BITRATE_PROCESSES[$i]}k completed"

		if [ "$LIVE_STREAM" == "1" ] && [ `$GREP 'EXT-X-ENDLIST' "$OUTPUT_DIRECTORY/${PLAYLIST_PREFIX}_${BITRATE_PROCESSES[$i]}.m3u8" | wc -l ` == "0" ]
		then
		    # Correctly terminate the manifest. See HLS-15 for info on why
		    echo "#EXT-X-ENDLIST" >> "$OUTPUT_DIRECTORY/${PLAYLIST_PREFIX}_${BITRATE_PROCESSES[$i]}.m3u8"
		    if [ "$?" != "0" ]
		    then
                        echo "Unable to terminate the manifest for bitrate ${BITRATE_PROCESSES[$i]}"
		    fi
		fi

		unset BITRATE_PROCESSES[$i]
		unset PIDS[$i]
	  fi
    done
    PIDS=("${PIDS[@]}") # remove any nulls
    BITRATE_PROCESSES=("${BITRATE_PROCESSES[@]}") # remove any nulls
    sleep 1
done
}

function encrypt(){
# Encrypt the generated segments with AES-128 bits


    # Only run the encryption routine if it's been enabled  (and not blocked)
    if [ ! "$ENCRYPT" == "1" ] || [ "$LIVE_STREAM" == "1" ]
    then
        return
    fi

    echo "Generating Encryption Key"
    KEY_FILE="$OUTPUT_DIRECTORY/${KEY_NAME}.key"

    openssl rand 16 > $KEY_FILE
    ENCRYPTION_KEY=$(cat $KEY_FILE | hexdump -e '16/1 "%02x"')

    echo "Encrypting Segments"
    for SEGMENT_FILE in ${OUTPUT_DIRECTORY}/*.ts
    do
        SEG_NO=$( echo "$SEGMENT_FILE" | $GREP -o -P '_[0-9]+\.ts' | tr -dc '0-9' )
        ENC_FILENAME="$OUTPUT_DIRECTORY/${SEGMENT_PREFIX}_enc_${SEG_NO}".ts

        # Strip leading 0's so printf doesn't think it's octal
        #SEG_NO=${SEG_NO##+(0)} # Doesn't work for some reason - need to check shopt to look further into it
        SEG_NO=$(echo $SEG_NO | $SED 's/^0*//' )
        
        # Convert the segment number to an IV. 
	INIT_VECTOR=$(printf '%032x' $SEG_NO)
	openssl aes-128-cbc -e -in $SEGMENT_FILE -out $ENC_FILENAME -nosalt -iv $INIT_VECTOR -K $ENCRYPTION_KEY

        # Move encrypted file to the original filename, so that the m3u8 file does not have to be changed
        mv $ENC_FILENAME $SEGMENT_FILE
        
    done

    echo "Updating Manifests"
    # this isn't technically correct as we needn't write into the master, but should still work
    for manifest in ${OUTPUT_DIRECTORY}/*.m3u8
    do
        # Insert the KEY at the 5'th line in the m3u8 file
        $SED -i "5i #EXT-X-KEY:METHOD=AES-128,URI=\"${KEY_PREFIX}${KEY_NAME}.key\"" "$manifest"
    done
}

# This is used internally, if the user wants to specify their own flags they should be
# setting FFMPEG_FLAGS or FFMPEG_INPUT_FLAGS
MYPID=$$
FFMPEG_ADDITIONAL=''
IGNORE_AUDIO=false
LIVE_SEGMENT_COUNT=0
IS_FIFO=0
TMPDIR=${TMPDIR:-"/tmp"}
MYPID=$$
TWOPASS=false
QUALITY=
CONSTANT=false
# Get the input data

# This exists to maintain b/c
LEGACY_ARGS=1

# If even one argument is supplied, switch off legacy argument style
while getopts "i:o:s:c:b:p:t:S:q:u:k:K:Clfe2n" flag
do
	LEGACY_ARGS=0
        case "$flag" in
                i) INPUTFILE="$OPTARG";;
                o) OUTPUT_DIRECTORY="$OPTARG";;
                s) SEGLENGTH="$OPTARG";;
		l) LIVE_STREAM=1;;
		c) LIVE_SEGMENT_COUNT="$OPTARG";;
		b) OP_BITRATES="$OPTARG";;
		f) NO_FORK=1;;
		p) PLAYLIST_PREFIX="$OPTARG";;
		t) SEGMENT_PREFIX="$OPTARG";;
		S) SEGMENT_DIRECTORY="$OPTARG";;
		e) ENCRYPT=1;;
		2) TWOPASS=true;;
		q) QUALITY="$OPTARG";;
		C) CONSTANT=true;;
		u) PATH_PREFIX="$OPTARG";;
		k) KEY_PREFIX="$OPTARG";;
		K) KEY_NAME="$OPTARG";;
		n) IGNORE_AUDIO=1;;
        esac
done


if [ "$LEGACY_ARGS" == "1" ]
then
  # Old Basic Usage is 
  # cmd.sh inputfile segmentlength 

  INPUTFILE=${INPUTFILE:-$1}
  SEGLENGTH=${SEGLENGTH:-$2}
  if ! [ -z "$3" ]
  then
    OUTPUT_DIRECTORY=$3
  fi
fi


# Check we've got the arguments we need
if [ "$INPUTFILE" == "" ] || [ "$SEGLENGTH" == "" ]
then
  print_usage
fi

# FFMpeg is a pre-requisite, so let check for it
if hash $FFMPEG 2> /dev/null
then
  # FFMpeg exists
  echo "ffmpeg command found.... continuing"
else
  # FFMPeg doesn't exist, uh-oh!
  echo "Error: FFmpeg doesn't appear to exist in your PATH. Please addresss and try again"
  exit 1
fi

# Check whether the input is a named pipe
if [ -p "$INPUTFILE" ]
then
  echo "Warning: Input is FIFO - EXPERIMENTAL"
  IS_FIFO=1
fi

# Make sure that the trailing slashes are added
if [ "$PATH_PREFIX" != "" ] && [ "${PATH_PREFIX:$length:1}" != "/" ]
then
  PATH_PREFIX+="/"
fi

if [ "$KEY_PREFIX" != "" ] && [ "${KEY_PREFIX:$length:1}" != "/" ]
then
  KEY_PREFIX+="/"
fi

# Check output directory exists otherwise create it
if [ ! -w $OUTPUT_DIRECTORY ]
then
  echo "Creating $OUTPUT_DIRECTORY"
  mkdir -p $OUTPUT_DIRECTORY
fi


if [ "$IGNORE_AUDIO" == "1" ]
then
    FFMPEG_ADDITIONAL+="-an "
fi

if [ "$LIVE_STREAM" == "1" ]
then
    FFMPEG_ADDITIONAL+="-segment_list_flags +live"

    if [ "$LIVE_SEGMENT_COUNT" -gt 0 ]
    then
	WRAP_POINT=$(($LIVE_SEGMENT_COUNT * 2)) # Wrap the segment numbering after 2 manifest lengths - prevents disks from filling
	FFMPEG_ADDITIONAL+=" -segment_list_size $LIVE_SEGMENT_COUNT -segment_wrap $WRAP_POINT"
    fi
fi


# HLS-33
#
# Handle Macs - it used to be possible to install gnu-sed and grep with default names using brew
# but they've changed the way you do that and it seems more inconsistent in terms of result
SED="sed"
command -v gsed >/dev/null 2>&1
if [ "$?" == "0" ]
then
    SED="gsed"
fi


GREP="grep"
command -v ggrep >/dev/null 2>&1
if [ "$?" == "0" ]
then
    GREP="ggrep"
fi



# Pulls file name from INPUTFILE which may be an absolute or relative path.
INPUTFILENAME=${INPUTFILE##*/}

# If a prefix hasn't been specified, use the input filename
PLAYLIST_PREFIX=${PLAYLIST_PREFIX:-$INPUTFILENAME}
SEGMENT_PREFIX=${SEGMENT_PREFIX:-$PLAYLIST_PREFIX}
KEY_NAME=${KEY_NAME:-$PLAYLIST_PREFIX}

# The 'S' option allows segments and bitrate specific manifests to be placed in a subdir
SEGMENT_DIRECTORY=${SEGMENT_DIRECTORY:-''}

if [ ! "$SEGMENT_DIRECTORY" == "" ]
then

	if [ ! -d "${OUTPUT_DIRECTORY}/${SEGMENT_DIRECTORY}" ]
	then
		mkdir "${OUTPUT_DIRECTORY}/${SEGMENT_DIRECTORY}"
	fi

	SEGMENT_DIRECTORY+="/"
	OUTPUT_DIRECTORY+="/"
fi

# Set the bitrate
if [ ! "$OP_BITRATES" == "" ]
then
      # Make the bitrate list easier to parse
      OP_BITRATES=${OP_BITRATES//,/$'\n'}

      # Create an array to house the pids for backgrounded tasks
      declare -a PIDS
      declare -a BITRATE_PROCESSES

      # Get the variant playlist created
      createVariantPlaylist "$OUTPUT_DIRECTORY/${PLAYLIST_PREFIX}_master.m3u8"
      for br in $OP_BITRATES
      do
            bw=$br
            if [[ "$br" == *"-"* ]]
            then
                bw=$(echo "$br" | cut -d- -f1) 
            fi
      
	    appendVariantPlaylistentry "$OUTPUT_DIRECTORY/${PLAYLIST_PREFIX}_master.m3u8" "${SEGMENT_DIRECTORY}${PLAYLIST_PREFIX}_${bw}.m3u8" "$br"
      done

      OUTPUT_DIRECTORY+=$SEGMENT_DIRECTORY

      # Now for the longer running bit, transcode the video
      for br in $OP_BITRATES
      do
      
              # Check whether there's a resolution included in the bitrate string
              #
              # See HLS-27
              if [[ "$br" == *"-"* ]]
              then
                resolution="-vf scale=$(echo "$br" | cut -d- -f2 | $SED 's/x/:/')"
                br=$(echo "$br" | cut -d- -f1) 
              fi
      
              if [ -z $QUALITY ]; then
		if $CONSTANT; then
	          BITRATE="-b:v ${br}k -bufsize ${br}k -minrate ${br}k -maxrate ${br}k"
		else
	          BITRATE="-b:v ${br}k"
		fi
	      else
	        BITRATE="-crf $QUALITY -maxrate ${br}k -bufsize ${br}k"
                if [ $VIDEO_CODEC = "libx265" ]; then
                  BITRATE="$BITRATE -x265-params --vbv-maxrate ${br}k --vbv-bufsize ${br}k"
                fi
	      fi
	      echo "Bitrate options: $BITRATE"
	      # Finally, lets build the output filename format
	      OUT_NAME="${SEGMENT_PREFIX}_${br}_%05d.ts"
	      PLAYLIST_NAME="$OUTPUT_DIRECTORY/${PLAYLIST_PREFIX}_${br}.m3u8"
	      SOURCE_FILE="$INPUTFILE"
	      echo "Generating HLS segments for bitrate ${br}k - this may take some time"

	      if [ "$NO_FORK" == "0" ] || [ "$LIVE_STREAM" == "1" ]
	      then
		      # Processing Starts
		      if [ "$IS_FIFO" == "1" ]
		      then
			    # Create a FIFO specially for this bitrate
			    SOURCE_FILE="$TMPDIR/hlsc.encode.$MYPID.$br"
			    mknod "$SOURCE_FILE" p
		      fi

		      # Schedule the encode
		      createStream "$PLAYLIST_NAME" "$OUT_NAME" "$BITRATE" "$SOURCE_FILE" "$TMPDIR/bw-$br.$MYPID.failfile" &
		      PID=$!
		      PIDS=(${PIDS[@]} $PID)
		      BITRATE_PROCESSES=(${BITRATE_PROCESSES[@]} $br)
	      else
		      createStream "$PLAYLIST_NAME" "$OUT_NAME" "$BITRATE" "$SOURCE_FILE" "$TMPDIR/bw-$BITRATE.$MYPID.failfile"
		      if [ -f "$TMPDIR/bw-$BITRATE.$MYPID.failfile" ]
		      then
                        echo "Error: FFMPEG exited with status code `cat $TMPDIR/bw-$BITRATE.$MYPID.failfile`"
                        rm -f "$TMPDIR/bw-$BITRATE.$MYPID.failfile"
                        exit 1
		      fi
	      fi

      done

      if [ "$IS_FIFO" == "1" ]
      then
	      # If the input was a FIFO we need to read from it and push into the new FIFOs
	      cat "$INPUTFILE" | tee $(for br in $OP_BITRATES; do echo "$TMPDIR/hlsc.encode.$MYPID.$br"; done) > /dev/null &
	      TEE_PID=$!
      fi

      if [ "$NO_FORK" == "0" ] || [ "$LIVE_STREAM" == "1" ]
      then
	    # Monitor the background tasks for completion
	    echo "All transcoding processes started, awaiting completion"
	    awaitCompletion
	    
	    # As of HLS-20 encrypt will only run if the relevant vars are set
	    encrypt
      fi

      if [ "$IS_FIFO" == "1" ]
      then
	    for br in $OP_BITRATES
	    do 
		rm -f "$TMPDIR/hlsc.encode.$MYPID.$br"; 
	    done
	    # If we were interrupted, tee may still be running
	    kill $TEE_PID 2> /dev/null 
      fi

else

  OUTPUT_DIRECTORY+=$SEGMENT_DIRECTORY
  # No bitrate specified

  # Finally, lets build the output filename format
  OUT_NAME="${SEGMENT_PREFIX}_%05d.ts"
  PLAYLIST_NAME="$OUTPUT_DIRECTORY/${PLAYLIST_PREFIX}.m3u8"

  echo "Generating HLS segments - this may take some time"

  # Processing Starts

  createStream "$PLAYLIST_NAME" "$OUT_NAME" "$BITRATE" "$INPUTFILE" "$TMPDIR/bw-$BITRATE.$MYPID.failfile"
  if [ -f "$TMPDIR/bw-$BITRATE.$MYPID.failfile" ]
  then
    echo "Error: FFMPEG exited with status code `cat $TMPDIR/bw-$BITRATE.$MYPID.failfile`"
    rm -f "$TMPDIR/bw-$BITRATE.$MYPID.failfile"
    exit 1
  fi  

  # As of HLS-20 encrypt will only run if the relevant vars are set
  encrypt
fi