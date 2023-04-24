#!/bin/sh
POSIXLY_CORRECT=yes

# Set default values
AFTER_DATE=""
BEFORE_DATE=""
GROUP=""
FILE=""
DIRECTORY=""
NOT_FILE_OR_DIR=""
MOST_FREQUENTLY_OPENED=false

IS_FILE=false
IS_DIRECTORY=false
NOT_FD=false #not file or dir flag

#Check if MOLE_RC variable is set
check_mole_rc(){
	if [ -z "$MOLE_RC" ]
	then
	        echo "Error: MOLE_RC is not set"
	        exit 1
	fi

	#Check if MOLE_RC file exists, create it if it doesn't
	if [ ! -f "$MOLE_RC" ]
	then
	        mkdir -p "$(dirname "$MOLE_RC")"
	        touch "$MOLE_RC"
	fi
}

# Determine which editor to use
editor_to_use(){
	if [ -n "$EDITOR" ]
	then
		editor="$EDITOR"
	elif [ -n "$VISUAL" ]
	then
		editor="$VISUAL"
	else
		editor="vi"
	fi
}



open_or_create_file() {
	#check if the FILE argument was got
	if [ -z "$1" ]; then #NO
		FILE=$(awk 'NR>0 {path=$1} END{if(NR>0){print path}}' "$MOLE_RC") #Read the first string of the last line of MOLE_RC file
		if [ -z "$FILE" ]; then
	     		echo "No file found in $MOLE_RC"
	      	return 1
	    	fi
	    	FILE=$(realpath "$FILE")
	    	echo "open_or_create_file: Opening file: $FILE"

	    	"$editor" "$FILE"

	else #YES
    		FILE=$(realpath "$1")
    		#echo "Opening file else: $FILE"

    		"$editor" "$FILE"

    		# file exists -> it can be added to the group
		if [ -n "$GROUP" ]; then
			if_group_exist "$GROUP"
			add_file_to_a_group "$FILE" "$GROUP"
		fi
  fi

  	update_mole_rc "$FILE"
}


# Function to update MOLE_RC with file information
update_mole_rc() {

	#echo "update_mole_rc function called with argument: $1"

    	file_path="$(realpath $1)" # get the real path of the file
    	file_info=$(grep "$file_path" "$MOLE_RC") # get the existing file info from MOLE_RC

    	if [ -z "$file_info" ]; then # if the file info doesn't exist in MOLE_RC, add it
        	echo "$file_path 1 $(date +%Y-%m-%d_%H-%M-%S ) $GROUP " >> "$MOLE_RC"
        	#echo "$file_path 1 $(date +%Y-%m-%d_%H-%M-%S )" >> "$MOLE_RC"

    	else # if the file info exists in MOLE_RC, update it
        	count=$(echo "$file_info" | awk '{print $2}')
        	count=$((count + 1))
        	last_access=$(date +%Y-%m-%d_%H-%M-%S)
       		sed -i "s|$file_info|$file_path $count $last_access $GROUP|g" "$MOLE_RC"

        	#sed -i "s|$file_info|$count $file_info $last_access|g" "$MOLE_RC"
    	fi
}


# Needs "$DIRECTORY" "$MOST_FREQUENTLY_OPENED"
mole_select_file() {

	echo "mole_select_file: dir var: $DIRECTORY"
	echo "mole_select_file: is_file: $IS_FILE"
	echo "mole_select_file: is_dir: $IS_DIRECTORY"

  if [ "$MOST_FREQUENTLY_OPENED" = true ] && ! $IS_DIRECTORY; then
    DIRECTORY=$(pwd)
    IS_DIRECTORY=true
  fi

  echo "MOST_FREQUENTLY_OPENED var: "$MOST_FREQUENTLY_OPENED""
  echo "mole_select_file: is_dir: $IS_DIRECTORY"
 	echo "mole_select_file: dir: $DIRECTORY"

  #in case ./mole.sh without any parameters
  if ! $IS_FILE && ! $IS_DIRECTORY && [ -z $NOT_FILE_OR_DIR ]; then
    DIRECTORY=$(pwd)
    IS_DIRECTORY=true
  fi

 	echo "mole_select_file: dir: $DIRECTORY"

	if [ ! -d "$DIRECTORY" ] ; then
		echo "Error: directory not found" >&2
		exit 1
	fi

 	if [ "$MOST_FREQUENTLY_OPENED" = true ]; then
    find_file_with_the_highest_count
  else
    find_last_modified_file
  fi

	echo "mole_select_file: file var: $FILE"
	echo "mole_select_file: dir var: $DIRECTORY"

}

find_file_with_the_highest_count() {
		FILE=$(grep "$DIRECTORY" "$MOLE_RC" | sort -t ' ' -k 2r | head -n 1 | cut -d ' ' -f 1)
		FILE="$FILE"
		echo "find_file_with_the_highest_count: file: $FILE"
}


find_last_modified_file() {

		echo "find_last_modified_file dir: $DIRECTORY"
	  last_opened_file=$(grep "$DIRECTORY[^/]*" "$MOLE_RC" | sort -t ' ' -k 3r | head -n 1 | cut -d ' ' -f 1)

		if [ -z "$last_opened_file" ]; then
    			echo "No files opened through script in $DIRECTORY directory."
			exit 1
		fi

		echo "Opening file: $last_opened_file"
		FILE="$last_opened_file"

}


if_group_exist() {
	# Check if the group with this name already exists
	if ! grep -qE "^$1:" /etc/group
	then
		#Create new group
		sudo groupadd "$1"
	fi
}

# Assign file to a group if provided;
# $1-FILE, $2-GROUP
add_file_to_a_group() {
	if [ -n "$2" ]; then
		chgrp "$2" "$1"
	fi
}


display_help() {
	echo "Usage:"
	echo "		mole -h"
	echo "		mole [-g GROUP] FILE"
	echo "		mole [-m] [FILTERS] [DIRECTORY]"
	echo "		mole list [FILTERS] [DIRECTORY]"
	echo ""
	echo "Options:"
	echo "	-h, --help		Display this help message."
	echo "	-g, --group GROUP	Set the file group."
	echo "	-m			Select the most frequently modified file."
	echo ""
	echo "Commands:"
	echo " 	list			List all files tracked by mole."
}


# Parse arguments
parse_arguments() {
	while getopts ":a:b:hg:m" opt
	do
		case $opt in
			a)
				AFTER_DATE="$OPTARG"
				;;
			b)
				BEFORE_DATE="$OPTARG"
				;;
			h)
				# Display help and exit
				display_help
				exit 0
				;;
			g)
				# Set the group variable to the provided value
				GROUP="$OPTARG"
				;;
			m)
				# Set the most frequently opened option
				MOST_FREQUENTLY_OPENED=true
				;;
			\?)
				echo "Invalid option: -$OPTARG" >&2
				display_help >&2
				exit 1
				;;
			:)
				echo "Option -$OPTARG" >&2
				display_help <&2
				exit 1
				;;
		esac
	done

	shift $((OPTIND-1))

	# Only one argument left should be the file/directory
	if [ $# -gt 1 ]; then
	  echo "Too many arguments!"
	  display_help
	  exit 1
	fi

	# Store the file argument or directory argument
	if [ -d "$1" ]; then # argument is directory
		DIRECTORY=$(realpath "$1")
		IS_DIRECTORY=true
	elif [ -f "$1" ]; then # argument is file

	  # -m is not allowed with FILE parameter
	  if $MOST_FREQUENTLY_OPENED; then
      echo "Illegal option '-m' for opening FILE."
      display_help
      exit 1;
    fi

	  FILE="$1"
	  IS_FILE=true
	else
	  NOT_FILE_OR_DIR="$1"
	  NOT_FD=true
	fi


}


#-----MAIN----------------------------------------------------

editor_to_use

check_mole_rc

parse_arguments "$@"

echo "args: $@"
echo "group var: $GROUP "
echo "dir var: $DIRECTORY"
echo "file var: $FILE"
echo "is_dir: $IS_DIRECTORY"
echo "is_file: $IS_FILE"
echo "not file or dir: $NOT_FILE_OR_DIR"
echo "not_fd: $NOT_FD"

if ! $IS_FILE; then
  mole_select_file
fi

echo "FILE: $FILE" # add this line to check if FILE variable is set correctly
open_or_create_file "$FILE"
