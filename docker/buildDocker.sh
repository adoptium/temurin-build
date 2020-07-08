#!/bin/bash
set -u

jdkVersion=''
bootDir=''
buildVariant="hotspot"
useEclipseOpenJ9DockerFiles=false
cleanWorkspace=false

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
				"--clean" | "-c" )
					cleanWorkspace=true;;
				"--version" | "-v" )
					jdkVersion="$1"; shift;;
				"--jdk-boot-dir" | "-J")
					bootDir="$1"; shift;;
				"--openj9" | "-j9")
					buildVariant="openj9";;
				"--use-eclipse-docker-files" | "-e" )
					useEclipseOpenJ9DockerFiles=true; buildVariant="eclipse";;
				"--help" | "-h" )
					usage; exit 0;;
				*) echo >&2 "Invalid option: ${opt}"; echo "This option was unrecognised."; usage; exit 1;;
			esac
		done
		checkArgs
	fi
}

usage()
{
	echo
	echo "Usage: ./buildDocker.sh	--all|-a 				Build all support JDK versions"
	echo "			--version|-v 				Build the specified JDK version"
	echo "			--clean | -c				Clean the old workspace"
	echo "			--jdk-boot-dir|-J			Specify the boot JDK directory"
	echo "			--openj9|-j9				Builds using OpenJ9 instead of Hotspot"
	echo "			--use-eclipse-docker-files|-e		Builds the specified jdk using the Eclipse Openj9 dockerfiles"
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
                "jdk14u" | "jdk14" | "14" | "14u" )
                        jdkVersion="jdk14";;
                "jdk" | "jdknext" )
                        jdkVersion="jdk";;
		"all" )
			jdkVersion="jdk8u jdk9u jdk10u jdk11u jdk12u jdk13u jdk14u jdk";;
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
		- jdk13u
		- jdk14u
		- jdk"
}

checkArgs()
{
	# Sets WORKSPACE to home if WORKSPACE is empty or unbounded
	if [ ! -n "${WORKSPACE:-}" ]; then
        	echo "WORKSPACE not found, setting it as environment variable 'HOME'"
        	WORKSPACE=$HOME
	fi
	if [ "$cleanWorkspace" == true ]; then
		echo "Cleaning workspace"
		rm -rf $WORKSPACE/DockerBuildFolder/$jdkVersion-$buildVariant
	fi
}

useEclipseOpenJ9DockerFiles()
{
	mkdir -p $WORKSPACE/DockerBuildFolder/$jdkVersion-$buildVariant/EclipseDockerfiles
	cd $WORKSPACE/DockerBuildFolder/$jdkVersion-$buildVariant/EclipseDockerfiles
	wget https://raw.githubusercontent.com/eclipse/openj9/master/buildenv/docker/mkdocker.sh
	chmod +x mkdocker.sh
	# Generate an Ubuntu1804 Dockerfile using mkdocker.sh
	$WORKSPACE/DockerBuildFolder/$jdkVersion-$buildVariant/EclipseDockerfiles/mkdocker.sh --dist=ubuntu --version=18 --print >> $WORKSPACE/DockerBuildFolder/$jdkVersion-$buildVariant/EclipseDockerfiles/Dockerfile
	
	# This Dockerfile requires an ssh key, authorized_key and known_hosts file to build
	ssh-keygen -q -f id_rsa -t rsa -N ''
	cat id_rsa.pub >> authorized_keys
	ssh-keyscan github.com >> $PWD/known_hosts

	# ${jdk%?} will remove the 'u' from 'jdkXXu'.
	for jdk in $jdkVersion
	do
		if [ ${jdk} != "jdk" ]; then
			jdk=${jdk%?}
		fi
		eclipseDockerCommands ${jdk}
	done
}

eclipseDockerCommands()
{
	local jdk=$1
	docker build -t ${jdk}-${buildVariant}-dfc -f Dockerfile .
	docker run -it -u root -d --name=${jdk}-${buildVariant} ${jdk}-${buildVariant}-dfc
	docker exec -u root -i ${jdk}-${buildVariant} sh -c "git clone https://github.com/ibmruntimes/openj9-openjdk-${jdk}"
	docker exec -u root -i ${jdk}-${buildVariant} sh -c "cd openj9-openjdk-${jdk} && bash ./get_source.sh && bash ./configure --with-freemarker-jar=/root/freemarker.jar && make all"
	docker stop ${jdk}-${buildVariant}
	docker rm ${jdk}-${buildVariant}
	docker rmi ${jdk}-${buildVariant}-dfc
}

buildDocker()
{
	local commandString="./makejdk-any-platform.sh --docker --clean-docker-build"
	if [ -n "$bootDir" ]; then
		commandString="$commandString -J $bootDir"
	fi
	if [[ "$buildVariant" == "openj9" ]]; then
		commandString="$commandString --build-variant openj9"
	fi
	for jdk in $jdkVersion
	do
		echo "$commandString $jdk being executed"
		cd $WORKSPACE/DockerBuildFolder/$jdk-$buildVariant && $commandString $jdk
	done
}

setupGit()
{
	if [ ! -d "$WORKSPACE/DockerBuildFolder/$jdkVersion-$buildVariant/docker" ]; then
		git clone https://github.com/adoptopenjdk/openjdk-build $WORKSPACE/DockerBuildFolder/$jdkVersion-$buildVariant
	else
		cd $WORKSPACE/DockerBuildFolder/$jdkVersion-$buildVariant
		git pull
	fi
}
parseCommandLineArgs $@
checkJDKVersion
mkdir -p $WORKSPACE/DockerBuildFolder/$jdkVersion-$buildVariant
if [[ "$useEclipseOpenJ9DockerFiles" == "true" ]]; then
	useEclipseOpenJ9DockerFiles
else
	setupGit
	buildDocker
fi
