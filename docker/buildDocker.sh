#!/bin/bash
set -u

jdkVersion=''
bootDir=''
openJ9=false
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
					openJ9=true;;
				"--use-eclipse-docker-files" | "-e" )
					useEclipseDockerFiles=true;;
				"--use-eclipse-docker-slave-files" | "-es" )
					useEclipseDockerSlavesFiles=true;;
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
		"all" )
			jdkVersion="jdk8u jdk9u jdk10u jdk11u jdk12u jdk13u";;
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

checkArgs()
{
	if [[ "$useEclipseDockerFiles" == true && "$useEclipseDockerSlavesFiles" == true ]]; then
		echo "Unable to use both kinds of dockerfiles at once, Select a single option."
		exit 1
        fi
}

useEclipseDockerFiles()
{
	cd $WORKSPACE/DockerBuildFolder/openjdk-build/docker && mkdir -p EclipseDockerfiles
	cd EclipseDockerfiles
	for jdk in $jdkVersion
	do
		# ${jdk%?} will remove the 'u' from 'jdk__u' when needed.
		curl -o Dockerfile.$jdk https://raw.githubusercontent.com/eclipse/openj9/master/buildenv/docker/${jdk%?}/x86_64/ubuntu16/Dockerfile;
		sharedDockerCommands $jdk
	done
}

useEclipseDockerSlavesFiles()
{
	cd $WORKSPACE/DockerBuildFolder/
	git clone https://github.com/eclipse/openj9 && cd openj9/buildenv/jenkins/docker-slaves/x86/centos6.9/
	if [ -f "known_hosts" ]; then 
		rm known_hosts
	fi
	ssh-keyscan github.com >> $PWD/known_hosts
	cp $HOME/.ssh/id_rsa.pub $PWD
	mv id_rsa.pub authorized_keys
	for jdk in $jdkVersion
	do
		cp Dockerfile $PWD/Dockerfile.$jdk
		sharedDockerCommands $jdk
	done
}

sharedDockerCommands()
{
	local jdk=$1
	docker build -t $jdk -f Dockerfile.$jdk .
	docker run -it -u root -d --name=$jdk $jdk
	docker exec -u root -it $jdk sh -c "git clone https://github.com/ibmruntimes/openj9-openjdk-${jdk%?}"
	docker exec -u root -it $jdk sh -c "cd openj9-openjdk-${jdk%?} && bash ./get_source.sh && bash ./configure --with-freemarker-jar=/root/freemarker.jar && make all"
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
	for jdk in $jdkVersion
	do
		echo "$commandString $jdk being executed"
		cd $WORKSPACE/DockerBuildFolder/openjdk-build && $commandString $jdk
	done
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
if [[ "$useEclipseDockerFiles" == "true" ]]; then
	useEclipseDockerFiles
elif [[ "$useEclipseDockerSlavesFiles" == "true" ]]; then
	useEclipseDockerSlavesFiles
else
	setupGit
	buildDocker
fi
