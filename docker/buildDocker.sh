#!/bin/bash
set -u

jdkVersion=''
bootDir=''
openJ9=false

#takes in all arguments to determine script options
parseCommandLineArgs()
{
	if [ $# -lt 1 ]; then
		echo "Script takes at least one argument"
		usage;
		exit 1;
	else
		while [[ $# -gt 0 ]] && [[ ."$1" = .-* ]] ; do
			local opt="$1";
			shift;
			case "$opt" in
				"--all" | "-a" )
					jdkVersion="all";;
				"--version" | "-v" )
					jdkVersion="$1"; shift;;
				"--jdk-boot-dir" | "-J")
					bootDir="$1"; shift;;
				"--openj9" | "-j9")
					openJ9=true;;
				"--help" | "-h" )
					usage; exit 0;;
				*) echo >&2 "Invalid option: ${opt}"; echo "This option was unrecognised."; usage; exit 1;;
			esac
		done
	fi
}

usage()
{
	echo
	echo "Usage: ./buildDocker.sh	--all|-a 		Build all support JDK versions"
	echo "			--version|-v 		Build the specified JDK version"
	echo "			--jdk-boot-dir|-J	Specify the boot JDK directory"
	echo "			--openj9|-j9		Builds using OpenJ9 instead of Hotspot"
	echo
}

checkJDKVersion()
{
	case "$jdkVersion" in
		"jdk8u" | "jdk8" | "8" | "8u" )
			jdkVersion="jdk8u";;
		"jdk9u" | "jdk9" | "9" | "9u" )
			jdkVersion="jdk9u";;
		"jdk10u" | "jdk10" | "10" | "10u" )
			jdkVersion="jdk10u";;
		"jdk11u" | "jdk11" | "11" | "11u" )
			jdkVersion="jdk11u";;
		"jdk12u" | "jdk12" | "12" | "12u" )
			jdkVersion="jdk12u";;
		"jdk13u" | "jdk13" | "13" | "13u" )
			jdkVersion="jdk13u";;
		"all" ) ;;
		*)
			echo "Not a valid JDK Version" ; jdkVersionList; exit 1;;
	esac
}

jdkVersionList()
{
	echo
	echo "Valid JDK versions :
		- jdk8u
		- jdk9u
		- jdk10u
		- jdk11u
		- jdk12u
		- jdk13u"
}

removeBuild()
{
	echo "Removing ../openjdk_build/workspace/build"
	cd $WORKSPACE/DockerBuildFolder/openjdk-build/workspace && rm -r build
}

buildDocker()
{
	local commandString="./makejdk-any-platform.sh --docker --clean-docker-build"
	if [ -n "$bootDir" ]; then
		commandString="$commandString -J $bootDir"
	fi
	if [[ "$openJ9" = true ]]; then
		commandString="$commandString --build-variant openj9"
	fi
	if [ "$jdkVersion" == "all" ]; then
		echo "Testing all Docker Builds"
		for jdk in jdk8u jdk9u jdk10u jdk11u jdk12u jdk13u
		do
			echo "$commandString $jdk being executed"
			cd $WORKSPACE/DockerBuildFolder/openjdk-build && $commandString $jdk
		done
	else
		echo "$commandString $jdkVersion being executed"
		cd $WORKSPACE/DockerBuildFolder/openjdk-build && $commandString $jdkVersion
	fi
	removeBuild
}

setupGit()
{
	mkdir -p $WORKSPACE/DockerBuildFolder
	cd $WORKSPACE/DockerBuildFolder/
	if [ ! -d "openjdk-build" ]; then
		git clone https://github.com/adoptopenjdk/openjdk-build $WORKSPACE/DockerBuildFolder/openjdk-build
	else
		cd openjdk-build
		git pull https://github.com/adoptopenjdk/openjdk-build
	fi
}

parseCommandLineArgs $@
checkJDKVersion
setupGit
buildDocker
