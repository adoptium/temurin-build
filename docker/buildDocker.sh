#!/bin/bash
set -u

jdkVersion=''
bootDir=''
buildVariant="hotspot"
useEclipseDockerFiles=false
useEclipseDockerSlavesFiles=false

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
					buildVariant="openj9";;
				"--use-eclipse-docker-files" | "-e" )
					useEclipseDockerFiles=true; buildVariant="eclipse";;
				"--use-eclipse-docker-slave-files" | "-es" )
					useEclipseDockerSlavesFiles=true; buildVariant="eclipse_slave";;
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
	echo "			--jdk-boot-dir|-J			Specify the boot JDK directory"
	echo "			--openj9|-j9				Builds using OpenJ9 instead of Hotspot"
	echo "			--use-eclipse-docker-files|-e		Builds the specified jdk using the Eclipse Openj9 dockerfiles"
	echo "			--use-eclipse-docker-slave-files|-es 	Builds the specified jdk using the Eclipse ../jenkins/docker-slaves dockerfiles"
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
                "jdk15u" | "jdk15" | "15" | "15u" )
                        jdkVersion="jdk";;
		"all" )
			jdkVersion="jdk8u jdk9u jdk10u jdk11u jdk12u jdk13u jdk14u jdk15u";;
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
		- jdk15u"
}

checkArgs()
{
	# Sets WORKSPACE to home if WORKSPACE is empty or unbounded
	if [ ! -n "${WORKSPACE:-}" ]; then
        	echo "WORKSPACE not found, setting it as environment variable 'HOME'"
        	WORKSPACE=$HOME
	fi
	if [[ "$useEclipseDockerFiles" == true && "$useEclipseDockerSlavesFiles" == true ]]; then
		echo "Unable to use both kinds of dockerfiles at once, Select a single option."
		exit 1
        fi
}

useEclipseDockerFiles()
{
	cd $WORKSPACE/DockerBuildFolder/$jdkVersion-$buildVariant && mkdir -p EclipseDockerfiles
	cd EclipseDockerfiles
	for jdk in $jdkVersion
	do
		# ${jdk%?} will remove the 'u' from 'jdk__u' when needed.
		curl -o Dockerfile.$jdk https://raw.githubusercontent.com/eclipse/openj9/master/buildenv/docker/${jdk%?}/x86_64/ubuntu16/Dockerfile;
		sharedEclipseDockerCommands $jdk
	done
}

useEclipseDockerSlavesFiles()
{
	cd $WORKSPACE/DockerBuildFolder/
	git clone https://github.com/eclipse/openj9 $WORKSPACE/DockerBuildFolder/$jdkVersion-$buildVariant 
	cd $WORKSPACE/DockerBuildFolder/$jdkVersion-$buildVariant/buildenv/jenkins/docker-slaves/x86/centos6.9
	if [ -f "known_hosts" ]; then 
		rm known_hosts
	fi
	ssh-keyscan github.com >> $PWD/known_hosts
	cp $HOME/.ssh/id_rsa.pub $PWD
	mv id_rsa.pub authorized_keys
	for jdk in $jdkVersion
	do
		cp Dockerfile $PWD/Dockerfile.$jdk
		sharedEclipseDockerCommands $jdk
	done
}

sharedEclipseDockerCommands()
{
	local jdk=$1
	docker build -t $jdk -f Dockerfile.$jdk .
	docker run -it -u root -d --name=${jdk}-Eclipse $jdk
	docker exec -u root -i ${jdk}-Eclipse sh -c "git clone https://github.com/ibmruntimes/openj9-openjdk-${jdk%?}"
	docker exec -u root -i ${jdk}-Eclipse sh -c "cd openj9-openjdk-${jdk%?} && bash ./get_source.sh && bash ./configure --with-freemarker-jar=/root/freemarker.jar && make all"
	docker stop ${jdk}-Eclipse
	docker rm ${jdk}-Eclipse
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
if [[ "$useEclipseDockerFiles" == "true" ]]; then
	useEclipseDockerFiles
elif [[ "$useEclipseDockerSlavesFiles" == "true" ]]; then
	useEclipseDockerSlavesFiles
else
	setupGit
	buildDocker
fi
