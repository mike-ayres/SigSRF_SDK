#!/bin/bash
#================================================================================================
# Bash script to install/uninstall SigSRF SDK and EdgeStream apps
# Copyright (C) Signalogic Inc 2017-2024
# Rev 1.8.3

# Requirements
   # Internet connection
   # Install unrar package -- handled automatically in unrarCheck() below, but if that fails ...
      # For Ubuntu, use command:
         # apt-get install unrar
      # For RHEL/CentOS,
         # yum -y install epel-release && rpm -Uvh http://li.nux.ro/download/nux/dextop/el7/x86_64/nux-dextop-release-0-5.el7.nux.noarch.rpm
         # yum install unrar

# Revision History
#  Created Feb 2016 HP
#  Modified Feb 2017 AM
#  Modified Aug 2018 JHB
#  Modified Sep 2019 JHB, fix issues in install menu options
#  Modified Sep 2020 JHB, correct various problems with unrar
#                         -if unrar was not installed the script was exiting both itself and the terminal window also (because script must be run as sourced)
#                         -add unrarCheck() function, which prompts to install unrar if needed
#                         -add depInstall_wo_dpkg() function, which does OS-dependent install based on line_pkg var
#                         -add method to install unrar for Ubuntu 17.04 and earlier, where unrar was in a weird repository due to licensing restrictions
#  Modified Sep 2020 JHB, fix problems with re-install (i.e. installing over existing files), including unrar command line, symlinks
#  Modified Sep 2020 JHB, other minor fixes, such as removing "cd -" commands after non DirectCore/lib installs (which are in a loop). Test in Docker containers, including Ubuntu 12.04, 18.04, and 20.04
#  Modified Jan 2021 JHB, fix minor issues in installCheckVerify(), add SIGNALOGIC_INSTALL_OPTIONS in /etc/environment, add preliminary check for valid .rar file
#  Modified Jan 2021 JHB, unrar only most recent .rar file in case user has downloaded before, look for .rar that matches installed distro
#  Modified Feb 2021 JHB, add ASR version to install options, add swInstallSetup(), fix problems in dependencyCheck(), add install path confirmation
#  Modified Jan 2022 JHB, add EdgeStream references
#  Modified Jan 2022 JHB, mods for CentOS 8, remove reference to specific gcc version
#  Modified Jan 2022 JHB, assume distro other than Ubunto or CentOS / RHEL as possible Ubuntu/Debian, let user know this is happening
#  Modified Mar 2022 JHB, set installOptions immediately after user menu and before any functions are called. Without this fix, if an ASR or coCPU package is selected, but the appropriate .rar is not found, no error message is given
#  Modified Aug 2022 JHB, add hello_codec to post-install build and "Apps check" section in installCheckVerify()
#  Modified Aug 2022 JHB, check exit status of unrar command
#  Modified Sep 2022 JHB, minor mods after testing Ubuntu .rar install on Debian 12.0
#  Modified Feb 2023 JHB, replace "target" terminology with "platform". Change order of hello_codec and mediaMin builds (mediaMin last)
#  Modified Feb 2023 JHB, fix coCPU symlink
#  Modified May 2023 JHB, add "no prompt" command line argument (look for use of noprompts var)
#  Modified Aug 2023 JHB, add symlink for mediaMin and mediaTest apps
#  Modified Dec 2023 JHB, add -f flag to lib cp commands, otherwise they might not overwrite during a re-install or upgrade. Note the use of "cp_prefix" to avoid alias cp commands on CentOS systems
#  Modified Mar 2024 JHB, for Debian unrar install add --allow-releaseinfo-change to apt-get update
#  Modified Apr 2025 JHB, add /etc/centos-release and "CentOS" to $OS string search to handle CentOS 6.x
#================================================================================================

depInstall_wo_dpkg() {

	if [ "$OS" = "Red Hat Enterprise Linux Server" -o "$OS" = "CentOS Linux" -o "$OS" = "CentOS" ]; then
		yum localinstall $line_pkg
#	elif [ "$platform" = "VM" -o "$OS" = "Ubuntu" ]; then
   else  # else includes Ubuntu, Debian, VM platform, or anything else
		apt-get install $line_pkg
	fi
}

packageSetup() { # check for .rar file and if found, prompt for Signalogic installation path, extract files

   # match SigSRF .rar files by ASR version and distro type, ignore the following:  JHB Jan2021
   #  -SDK vs license
   #  -host vs VM
   #  -distro version and date

	if [ "$OS" = "Red Hat Enterprise Linux Server" -o "$OS" = "CentOS Linux" -o "$OS" = "CentOS" ]; then
		if [ "$installOptions" = "ASR" ]; then  # demo includes automatic speech recognition
			rarFile="Signalogic_sw_host_SigSRF_*_ASR_*CentOS*.rar"
		else
			rarFile="Signalogic_sw_host_SigSRF_*CentOS*.rar"
		fi
	else  # add other distro types as needed.  Currently Debian defaults to Ubuntu .rar, with some minor differences (look for "Debian" below), JHB Jan2021
		if [ "$installOptions" = "ASR" ]; then
			rarFile="Signalogic_sw_host_SigSRF_*_ASR_*Ubuntu*.rar"
		else
			rarFile="Signalogic_sw_host_SigSRF_*Ubuntu*.rar"
		fi
	fi

   # unrar only most recent .rar file found (also this avoids unraring more than one file, due to wildcard), JHB Jan2021
   # notes - Github doesn't support last-modified headers (has been that way for years), so wget and curl are unable to preserve the file date. But we still search for most recent .rar as a best practice

	rarFileNewest=""
	for iFileName in `ls -tr $rarFile`; do
		rarFileNewest=$iFileName;
	done;

	if [ "$rarFileNewest" = "" ]; then  # add check for incorrect or no .rar files found, JHB Jan2021
		echo "Install rar package file not found"
		return 0
	fi

   if [ -z "$noprompts" ]; then  # prompt for install path if nopromopts empty

      echo  # print blank line, lots of stuff may be displayed just before the path prompt

	   while true; do

		   echo "Enter path for SigSRF and EdgeStream software and dependency package installation:"
		   read installPath

		   if [ ! $installPath ]; then
		      installPath="/usr/local"  # default if nothing entered
		   fi

         read -p "Please confirm install path $installPath [Y] or [N] " Confirm

         case $Confirm in
			   [Yy]* ) break;;
		   esac
	   done

   else  # otherwise default to install path used in Docker containers

      installPath="/home/sigsrf_sdk_demo"
   fi

	return 1
}

unrarCheck() {

   unrar_status="uninitialized"
	unrarInstalled=`type -p unrar`  # see if unrar is recognized on cmd line

	if [ "$unrarInstalled" == "" ]; then  # if not then need to install

	   while true; do

         if [ -z "$noprompts" ]; then  # prompt for unrar install if noprompts empty
			   read -p "Unrar not installed, ok to install now ?" yn
         else
            yn="Y"  # otherwise default to Yes
         fi

			case $yn in

				[Yy]* ) line_pkg="unrar"

   				depInstall_wo_dpkg;  # try package install

               unrarInstalled=`type -p unrar`  # recheck

	            if [ "$unrarInstalled" == "" ]; then  # if still not installed, then try non-package methods

                  if [ "$OS" = "Red Hat Enterprise Linux Server" -o "$OS" = "CentOS Linux" -o "$OS" = "CentOS" ]; then

                     echo "Attempting to install rarlab unrar ..."

            	   	wgetInstalled=`type -p wget`  # wget should already be installed, but check anyway
			            if [ "$wgetInstalled" == "" ]; then
                        echo "wget not found, attempting to install ..."
                        apt-get install wget
                     fi

                     wget --no-check-certificate https://www.rarlab.com/rar/rarlinux-x64-6.0.2.tar.gz
                     tar -zxvf rarlinux-x64-6.0.2.tar.gz
                     mv rar/rar rar/unrar /usr/local/bin/

                  elif [ "$OS" = "Debian GNU/Linux" ]; then

                     echo "Attempting to install non-free unrar for Debian ..."

            		   wgetInstalled=`type -p wget`  # wget should already be installed, but check anyway
			            if [ "$wgetInstalled" == "" ]; then
                        echo "wget not found, attempting to install ..."
                        apt-get install wget && apt-get -y install gnupg
                     fi

                     # add unrar install for Debian, JHB Sep 2022

                     wget -qO - https://ftp-master.debian.org/keys/archive-key-10.asc | apt-key add - \
                        && echo deb http://deb.debian.org/debian buster main contrib non-free | tee -a /etc/apt/sources.list \
                        && apt-get update --allow-releaseinfo-change \
                        && apt-get install unrar

                  else  # includes Ubuntu, VM platform, or anything else

                     echo "Attempting to install older version of unrar ..."  # old version of unrar was called "unrar-nonfree" due to licensing restrictions, Linux guys hate that enough they stuck it in the Necromonger underverse (well, close)
                     sed -i "/^# deb .* multiverse$/ s/^# //" /etc/apt/sources.list; apt-get update
                     depInstall_wo_dpkg;
                  fi

					   if [[ $? = 0 ]]; then
						   unrar_status="install"
					   fi;
				   else
					   unrar_status="already installed"
				   fi
				   break;;

				[Nn]* ) unrar_status="don't install";;

				* ) echo "Please enter y or n";;
			esac
		done
	else
		unrar_status="already installed"
	fi

   if [[ "$unrar_status" == "install" || "$unrar_status" == "already installed" ]]; then  # unrar in both of these cases, for example the Signalogic/etc folder gets deleted, and unrar restores it. Unrar'ing doesn't take long
      if unrar x -o+ $rarFileNewest $installPath/; then # assumes packageSetup() has been called first, and rarFileNewest and installPath have been set
         return 1
      else
         echo "unrar error"
         return 0
      fi
   elif [[ "$unrar_status" == "uninitialized" ]]; then
      echo "internal problem in unrarCheck()"
      return 0
   else
      return 0  # user doesn't want to install
   fi
}

depInstall() {

	if [ "$OS" = "Red Hat Enterprise Linux Server" -o "$OS" = "CentOS Linux" -o "$OS" = "CentOS" ]; then
		yum localinstall $line
#	elif [ "$platform" = "VM" -o "$OS" = "Ubuntu" ]; then
   else  # else includes Ubuntu, Debian, VM platform, or anything else
		dpkg -i $line
		if [ $? -gt 0 ]; then
			apt-get -f --force-yes --yes install  # package name not needed if run immediately after dpkg, JHB Sep2020
		fi
	fi
}

swInstallSetup() {  # basic setup needed by both dependencyCheck() and swInstall()

   # Set up environment vars, save install path and install options in env vars

	export SIGNALOGIC_INSTALL_PATH=$installPath
	sed -i '/SIGNALOGIC_INSTALL_PATH*/d' /etc/environment  # first remove any install paths already there, JHB Jan2021
	echo "SIGNALOGIC_INSTALL_PATH=$installPath" >> /etc/environment
	export SIGNALOGIC_INSTALL_OPTIONS=$installOptions
	sed -i '/SIGNALOGIC_INSTALL_OPTIONS*/d' /etc/environment  # first remove any install options already there, JHB Jan2021
	echo "SIGNALOGIC_INSTALL_OPTIONS=$installOptions" >> /etc/environment
	
	echo
	echo "Installing SigSRF and EdgeStream software ..."
	mv -f $installPath/Signalogic_*/etc/signalogic /etc
	rm -rf $installPath/Signalogic*/etc
	echo
	echo "Creating symlinks..."

	if [ "$OS" = "Red Hat Enterprise Linux Server" -o "$OS" = "CentOS Linux" -o "$OS" = "CentOS" ]; then
		if [ ! -L /usr/src/linux ]; then
			ln -s /usr/src/kernels/$kernel_version /usr/src/linux
		fi 
#	elif [ "$OS" = "Ubuntu" ]; then
   else  # else includes Ubuntu, Debian, VM platform, or anything else
		if [ ! -L /usr/src/linux ]; then
			ln -s /usr/src/linux-headers-$kernel_version /usr/src/linux
		fi
	fi

   # Create symlinks. Assume _2xxx (year) in the name, otherwise ln command might try to symlink the .rar file :-(

	if [ ! -L $installPath/Signalogic ]; then
		ln -s $installPath/Signalogic_2* $installPath/Signalogic
	fi

	if [ ! -L $installPath/Signalogic/apps ]; then
		ln -s $installPath/Signalogic_2*/DirectCore/apps/SigC641x_C667x $installPath/Signalogic/apps
	fi

	if [ ! -L $installPath/Signalogic/coCPU ]; then
		ln -s $installPath/Signalogic_2*/mCPU_target $installPath/Signalogic/coCPU 
	fi

	if [ ! -L /bin/mediaMin ]; then  # add system-wide symlink for mediaMin JHB Aug 2023
      ln -sfn $installPath/Signalogic/apps/mediaTest/mediaMin/mediaMin /bin/mediaMin
	fi

	if [ ! -L /bin/mediaTest ]; then  # add system-wide symlink for mediaTest JHB Mar 2024
      ln -sfn $installPath/Signalogic/apps/mediaTest/mediaTest /bin/mediaTest
	fi
}

dependencyCheck() {  # Check for generic sw packages and prompt for installation if not installed

	echo
	echo "Dependency check..."

	DOTs='................................................................'
	
	if [[ "$opt" == "Install"* ]]; then  # to handle ASR and coCPU options, use wildcard to find first part of string (note -- didn't get white spaces working yet), JHB Feb2021

		dependencyInstall="Dependency Check + Install"

	elif [ "$opt" = "Dependency Check" ]; then  # currently this is a deprecated install option

		installPath=$(grep -w "SIGNALOGIC_INSTALL_PATH=*" /etc/environment | sed -n -e '/SIGNALOGIC_INSTALL_PATH/ s/.*\= *//p')
		dependencyInstall="Dependency Check"
      gcc_package=""

		if [ ! $installPath ]; then
			echo 
			echo "SigSRF / EdgeStream software install path not found"
			echo
			return 0
		fi
	fi

	if [ "$dependencyInstall" = "Dependency Check + Install" ]; then

      if [[ "$OS" != "Ubuntu" && "$OS" != "Red Hat Enterprise Linux Server" && "$OS" != "CentOS Linux" && "$OS" != "CentOS" ]]; then
         echo
         echo "Distro $OS is not Ubuntu or CentOS / RHEL; attempting to install assuming Ubuntu / Debian derivative ..."
      fi

      gcc_package=$(/usr/bin/g++ --version 2>/dev/null | grep g++ | awk ' {print $1} ')  # EdgeStream Makefiles expect /usr/bin/g++ to work, install script expects Makefiles to work

      if [ "$gcc_package" == "" ]; then

         gcc_package=$(g++ --version 2>/dev/null | grep g++ | awk ' {print $1} ')

         if [ "$gcc_package" != "" ]; then

            gpp_path=$(which g++)
            ln -s $gpp_path /usr/bin/g++  # set necessary symlink
         else
            if [ "$OS" = "Red Hat Enterprise Linux Server" -o "$OS" = "CentOS Linux" -o "$OS" = "CentOS" ]; then
               gcc_package=$(rpm -qa gcc-c++)  # generic g++ package check, should come back with version installed
            else
               gcc_package=$(dpkg -s g++ 2>/dev/null | grep Status | awk ' {print $4} ')  # generic g++ package check, should come back with "installed"
            fi
         fi
      fi

      if [ "$gcc_package" == "" ]; then

         echo -e "/usr/bin/g++ not found, gcc/g++ compilers and toolchain are needed\n"

         if [ -z "$noprompts" ]; then  # prompt for gcc install if noprompts empty
   			read -p "Install gcc/g++ tools now [Y]es, [N]o ?" Dn
         else
            Dn="Y"  # otherwise default to Yes
         fi

			if [[ ($Dn = "y") || ($Dn = "Y") ]]; then

            if [ "$OS" = "Red Hat Enterprise Linux Server" -o "$OS" = "CentOS Linux" -o "$OS" = "CentOS" ]; then
               yum install gcc-c++
               gcc_package=$(rpm -qa gcc-c++)  # recheck
            else
               apt-get install build-essential  # to-do: not likely to work on old Ubuntu distros
               gcc_package=$(dpkg -s g++ 2>/dev/null | grep Status | awk ' {print $4} ')  # recheck
            fi
			fi
   	fi

      if [ "$OS" = "Ubuntu" ]; then  # lsb-release package needed only for Ubuntu (not CentOS, Debian, etc)

  			lsbReleaseInstalled=`type -p lsb_release`
			if [ "$lsbReleaseInstalled" == "" ]; then
		  		echo "lsb-release package is needed, installing ..."
				apt-get install lsb-release
			fi
		fi
   fi
	
	if [ "$OS" = "Red Hat Enterprise Linux Server" -o "$OS" = "CentOS Linux" -o "$OS" = "CentOS" ]; then
	{
		cd $installPath/Signalogic/installation_rpms/RHEL
		filename="rhelDependency.txt"
   }
   else {
		cd $installPath/Signalogic/installation_rpms/Ubuntu
		filename="UbuntuDependency.txt"
   }
   fi

   while read -r -u 3 line
	do

		d=$(sed 's/_.*//g' <<< $line)
		if [[ "$d" == "make" ]]; then
			e=$d
		else
         if [[ "$d" == *"-devel-"* ]]; then
			   e=$(sed 's/-/~/1' <<< $line)  # search for second "-" and truncate to set e with generic developer package name. The 3-step hack can be replaced with a one-line sed that handles 2nd ocurrence correctly
			   e=$(sed 's/-.*//g' <<< $e)
			   e=$(sed 's/~/-/1' <<< $e)
         else
            e=$(sed 's/-.*//g' <<< $line)  # search for first "-" and truncate to set e with generic package name
         fi
		fi

		package=$(dpkg -s $e 2>/dev/null | grep Status | awk ' {print $4} ')

		if [[ ( "$e" == "libncurses"* || "$e" == "ncurses"* || "$e" == "libncurses-devel"* || "$e" == "ncurses-devel"* ) && "$installOptions" != "coCPU" ]]; then  # libncurses only referenced in memTest Makefile
			package="not needed"
		fi

		if [[ ( "$e" == "libexplain"* || "$e" == "libexplain-devel"* ) && "$installOptions" != "coCPU" ]]; then  # libexplain only referenced in streamTest Makefile
			package="not needed"
		fi

		if [[ ("$e" == "gcc"* || "$e" == "g++"*) && "$gcc_package" != "" ]]; then  # gcc/g++ of some version already installed. Since we retro-test back to 4.6 (circa 2011), we don't worry about minimum version
			package="already installed"
		fi

		if [ "$package" == "" ]; then
			if [ "$dependencyInstall" = "Dependency Check + Install" ]; then
				if [ ! $totalInstall ]; then

               if [ -z "$noprompts" ]; then  # prompt for package install if noprompts empty
   					read -p "Do you wish to install $e package? Please enter [Y]es, [N]o, [A]ll: " Dn
               else
                  Dn="Y"  # otherwise default to Yes
               fi

					if [[ ($Dn = "a") || ($Dn = "A") ]]; then
						totalInstall=1
					fi
				fi
				case $Dn in
					[YyAa]* ) depInstall ; ;;  # depInstall uses "line" var
					[Nn]* ) ;;
					* ) echo "Please retry with just y, n, or a";;
				esac
			elif [ "$dependencyInstall" = "Dependency Check" ]; then
				printf "%s %s[ NOT INSTALLED ]\n" $e "${DOTs:${#e}}"
			fi
		elif [ "$package" = "not needed" ]; then
			printf "%s %s[ NOT NEEDED ]\n" $e "${DOTs:${#e}}"
		else
			printf "%s %s[ ALREADY INSTALLED ]\n" $e "${DOTs:${#e}}"
   	fi
	done 3< "$filename"

#	if [ "$dependencyInstall" = "Dependency Check + Install" ]; then
#		# Dependencies gcc and g++ will be installed as gcc-4.8 and g++-4.8 so it is necessary to create a symmlink (gcc and g++) otherwise SW installation might fail
#		if [ ! -L  /usr/bin/gcc ]; then
#	  	  	ln -s /usr/bin/gcc-4.8 /usr/bin/gcc
#		fi
#		if [ ! -L  /usr/bin/g++ ]; then
#			ln -s /usr/bin/g++-4.8 /usr/bin/g++
#		fi
#	fi
}

swInstall() {  # install Signalogic SW on specified path

# note -- assumes dependencyCheck() and swInstallSetup() have run

   if [ "$OS" = "CentOS Linux" -o "$OS" = "Red Hat Enterprise Linux Server" -o "$OS" = "CentOS" ]; then
      cp_prefix="/bin/"
#   elif [ "$OS" = "Ubuntu" ]; then
   else  # else includes Ubuntu, Debian, VM platform, or anything else
      cp_prefix=""
   fi

	if [ "$installOptions" = "coCPU" ]; then

		echo
		echo "Loading coCPU driver ..."
		echo

		if [ "$platform" = "Host" ]; then

         if [ "$OS" = "Red Hat Enterprise Linux Server" -o "$OS" = "CentOS Linux" -o "$OS" = "CentOS"]; then
            distribution=$(cat /etc/centos-release)
         elif [ "$OS" = "Ubuntu" -a "$lsbReleaseInstalled" != "" ]; then
            distribution=$(cat /etc/lsb-release)
         else  # else includes Debian, VM platform, or anything else
            distribution=$(cat /etc/os-release)  # os-release is supposedly the Linux standard
         fi

			cd $installPath/Signalogic/DirectCore/hw_utils; make
			cd ../driver; 
			kernel=$(uname -r) 

			if [[ $kernel == 3.2.0-49-generic ]]; then
				cp sig_mc_hw_ubuntu_12.04.5.ko sig_mc_hw.ko
			elif [[ $kernel == 3.16.0-67-generic ]]; then
				cp sig_mc_hw_ubuntu_14.04.4.ko sig_mc_hw.ko
			elif [[ $kernel == 4.4.0-31-generic ]]; then
				cp sig_mc_hw_ubuntu_14.04.5.ko sig_mc_hw.ko
			elif [[ $kernel == "4.4.0-59-generic" ]]; then
				cp sig_mc_hw_ubuntu_16.04.1.ko sig_mc_hw.ko
			elif [[ $distribution == *12.04.5* ]]; then
				cp sig_mc_hw_ubuntu_12.04.5.ko sig_mc_hw.ko
			elif [[ $distribution == *14.04.4* ]]; then
				cp sig_mc_hw_ubuntu_14.04.4.ko sig_mc_hw.ko
			elif [[ $distribution == *14.04.5* ]]; then
				cp sig_mc_hw_ubuntu_14.04.5.ko sig_mc_hw.ko
			elif [[ $distribution == *16.04.1* ]]; then
				cp sig_mc_hw_ubuntu_16.04.1.ko sig_mc_hw.ko
			fi

			make load;  # load driver -- note if already loaded then an error message is shown, but causes no problems, JHB Jan2021
			echo

			if lsmod | grep sig_mc_hw &> /dev/null ; then
				echo "coCPU driver is loaded"
				echo
			fi
		elif [ "$platform" = "VM" ]; then
			cd $installPath/Signalogic/DirectCore/virt_driver;
			make load;
			echo
		fi

		echo "Setting up autoload of coCPU driver on boot"

		if [ "$platform" = "Host" ]; then
			if [ ! -f /lib/modules/$kernel_version//sig_mc_hw.ko ]; then
				ln -s $installPath/Signalogic/DirectCore/driver/sig_mc_hw.ko /lib/modules/$kernel_version
			fi
		elif [ "$platform" = "VM" ]; then
			if [ ! -L /lib/modules/$kernel_version ]; then
				ln -s $installPath/Signalogic/DirectCore/virt_driver/virtio-sig.ko /lib/modules/$kernel_version
			fi
		fi

		depmod -a

		if [ "$OS" = "CentOS Linux" -o "$OS" = "Red Hat Enterprise Linux Server" -o "$OS" = "CentOS" ]; then
			cp -p $installPath/Signalogic/DirectCore/driver/sig_mc_hw.modules /etc/sysconfig/modules/
			chmod 755 /etc/sysconfig/modules/sig_mc_hw.modules
			echo "chmod 666 /dev/sig_mc_hw" >> /etc/rc.d/rc.local
			chmod 755 /etc/rc.d/rc.local
#		elif [ "$OS" = "Ubuntu" ]; then
      else  # else includes Ubuntu, Debian, VM platform, or anything else
			echo "sig_mc_hw" >> /etc/modules
			sed -i '/exit*/d' /etc/rc.local
			echo "chmod 666 /dev/sig_mc_hw" >> /etc/rc.local
			echo "exit 0" >> /etc/rc.local
			chmod 755 /etc/rc.local
		fi
	fi

	echo
	echo "Installing SigSRF libs for packet handling, stream group processing, inference, diagnostic, etc..."
	echo

	cd $installPath/Signalogic/DirectCore/lib/
	for d in *; do
		cd $d; "$cp_prefix"cp -p -f lib* /usr/lib; ldconfig; cd ~-; cd -; cd ~-  # go back with no output, then go to subfolder again to show it onscreen, then go back and continue
	done

	echo
	echo "Installing SigSRF codec libs..."
	cd $installPath/Signalogic/SIG_LIBS/Voice/AMR/lib 2>/dev/null
	"$cp_prefix"cp -p -f lib* /usr/lib 2>/dev/null;
	cd $installPath/Signalogic/SIG_LIBS/Voice/AMR-WB/lib 2>/dev/null
	"$cp_prefix"cp -p -f lib* /usr/lib 2>/dev/null;
	cd $installPath/Signalogic/SIG_LIBS/Voice/AMR-WB+/lib 2>/dev/null
	"$cp_prefix"cp -p -f lib* /usr/lib 2>/dev/null;
	cd $installPath/Signalogic/SIG_LIBS/Voice/EVS_floating-point/lib 2>/dev/null
	"$cp_prefix"cp -p -f lib* /usr/lib 2>/dev/null;
	cd $installPath/Signalogic/SIG_LIBS/Voice/G726/lib 2>/dev/null
	"$cp_prefix"cp -p -f lib* /usr/lib 2>/dev/null;
	cd $installPath/Signalogic/SIG_LIBS/Voice/G729AB/lib 2>/dev/null
	"$cp_prefix"cp -p -f lib* /usr/lib 2>/dev/null;
	cd $installPath/Signalogic/SIG_LIBS/Voice/MELPe_floating-point/lib 2>/dev/null
	"$cp_prefix"cp -p -f lib* /usr/lib 2>/dev/null;
	ldconfig;

	echo
	echo "Building EdgeStream applications..."
   echo

	if [ "$installOptions" = "coCPU" ]; then

		cd $installPath/Signalogic/apps/memTest
		make clean; make all;

		cd $installPath/Signalogic/apps/boardTest
		make clean; make all;

		cd $installPath/Signalogic/apps/streamTest
		make clean; make all;
	fi

	cd $installPath/Signalogic/apps/iaTest
	make clean; make all;

	cd $installPath/Signalogic/apps/mediaTest/hello_codec
	make clean; make all;

	cd $installPath/Signalogic/apps/mediaTest
	make clean; make all;

	cd $installPath/Signalogic/apps/mediaTest/mediaMin
	make clean; make all;

	cd $startPath
}

unInstall() { # uninstall Signalogic SW completely

	OS=$(cat /etc/os-release | grep -w NAME=* | sed -n -e '/NAME/ s/.*\= *//p' | sed 's/"//g')
   if [ -z "$OS" ]; then
      OS=$(cat /etc/centos-release | grep -w CentOS* | sed 's/ .*//')  # CentOS before 7 seems to not have /cat/os-release folder. Add any other OS releases here, keep checking for $OS empty, JHB Apr 2025
   fi
	echo
	echo "Uninstalling SigSRF and EdgeStream software..."
	echo
	unInstallPath=$SIGNALOGIC_INSTALL_PATH
	if [ ! $unInstallPath ]; then
		unInstallPath=$(grep -w "SIGNALOGIC_INSTALL_PATH=*" /etc/environment | sed -n -e '/SIGNALOGIC_INSTALL_PATH/ s/.*\= *//p')
		if [ ! $unInstallPath ]; then
			echo 
			echo "Signalogic install path not found"
			echo
			return 0
		fi
	fi

	unInstallOptions=$SIGNALOGIC_INSTALL_OPTIONS
	if [ ! $unInstallOptions ]; then
		unInstallOptions=$(grep -w "SIGNALOGIC_INSTALL_OPTIONS=*" /etc/environment | sed -n -e '/SIGNALOGIC_INSTALL_OPTIONS/ s/.*\= *//p')
	fi
	
	echo "Signalogic Install Path: $unInstallPath"
	rm -rf $unInstallPath/Signalogic*
	rm -rf /etc/signalogic

	if [ "$uninstallOptions" = "coCPU" ]; then

		rmmod sig_mc_hw
		unlink /usr/src/linux
	
		if [ "$OS" = "CentOS Linux" -o "$OS" = "Red Hat Enterprise Linux Server" -o "$OS" = "CentOS" ]; then
			rm -rf /etc/sysconfig/modules/sig_mc_hw.modules
		fi
	
		if [ "$OS" = "CentOS Linux" -o "$OS" = "Red Hat Enterprise Linux Server" -o "$OS" = "CentOS" ]; then
			if [ $platform = "Host" ]; then
				rm -rf /usr/lib/modules/$kernel_version/sig_mc_hw.ko
			elif [ $platform = "VM" ]; then
				rm -rf /usr/lib/modules/$kernel_version/virtio-sig.ko
			fi
#		elif [ "$OS" = "Ubuntu" ]; then
      else  # else includes Ubuntu, Debian, VM platform, or anything else
			if [ $platform = "Host" ]; then
				rm -rf /lib/modules/$kernel_version/sig_mc_hw.ko
			elif [ $platform = "VM" ]; then
				rm -rf /lib/modules/$kernel_version/virtio-sig.ko
			fi
		fi
	
		if [ "$OS" = "CentOS Linux" -o "$OS" = "Red Hat Enterprise Linux Server" -o "$OS" = "CentOS" ]; then
			sed -i '/chmod 666 \/dev\/sig_mc_hw/d' /etc/rc.d/rc.local 
#		elif [ "$OS" = "Ubuntu" ]; then
      else  # else includes Ubuntu, Debian, VM platform, or anything else
			sed -i '/chmod 666 \/dev\/sig_mc_hw/d' /etc/rc.local
		fi
	fi

	rm -rf /usr/lib/libcimlib*
	rm -rf /usr/lib/libhwmgr*
	rm -rf /usr/lib/libfilelib*
	rm -rf /usr/lib/libhwlib*
	rm -rf /usr/lib/libpktib*
	rm -rf /usr/lib/libvoplib*
	rm -rf /usr/lib/libalglib*
	rm -rf /usr/lib/libinferlib*
	rm -rf /usr/lib/libaviolib*
	rm -rf /usr/lib/libdiaglib*
	rm -rf /usr/lib/libstublib*
	rm -rf /usr/lib/libtdmlib*

	unset SIGNALOGIC_INSTALL_PATH
	sed -i '/SIGNALOGIC_INSTALL_PATH*/d' /etc/environment
	unset SIGNALOGIC_INSTALL_OPTIONS
	sed -i '/SIGNALOGIC_INSTALL_OPTIONS*/d' /etc/environment

	echo "Uninstall complete..."
}

diagLibPrint() {

	if [ -f /usr/lib/"$libfile" ]; then
		printf "%s %s[ OK ]\n" $libname "${line:${#libname}}" | tee -a $diagReportFile
	else
		printf "%s %s[ X ]\n" $libname "${line:${#libname}}" | tee -a $diagReportFile
	fi
}

diagAppPrint() {

	if [ -f $installPath/Signalogic/apps/"$appfile"/"$appname" ]; then
		printf "%s %s[ OK ]\n" $appname "${line:${#appname}}" | tee -a $diagReportFile
	else
		printf "%s %s[ X ]\n" $appname "${line:${#appname}}" | tee -a $diagReportFile
	fi
}

installCheckVerify() {

	line='................................................................'

	installPath=$SIGNALOGIC_INSTALL_PATH
	if [ ! $installPath ]; then
		installPath=$(grep -w "SIGNALOGIC_INSTALL_PATH=*" /etc/environment | sed -n -e '/SIGNALOGIC_INSTALL_PATH/ s/.*\= *//p')
		if [ ! $installPath ]; then
			echo 
			echo "Signalogic install path not found"
			echo
			return 0
		fi
	fi

	installOptions=$SIGNALOGIC_INSTALL_OPTIONS
	if [ ! $installOptions ]; then
		installOptions=$(grep -w "SIGNALOGIC_INSTALL_OPTIONS=*" /etc/environment | sed -n -e '/SIGNALOGIC_INSTALL_OPTIONS/ s/.*\= *//p')
	fi

	current_time=$(date +"%m.%d.%Y-%H:%M:%S")
	diagReportFile=DirectCore_diagnostic_report_$current_time.txt
	touch $diagReportFile

	# Path check

	echo
	echo "Distro Info" | tee -a $diagReportFile
   lsbreleaseInstalled=`type -p lsb_release`

   if [ "$OS" = "Red Hat Enterprise Linux Server" -o "$OS" = "CentOS Linux" -o "$OS" = "CentOS" ]; then
      cat /etc/centos-release | tee -a $diagReportFile
   elif [ "$OS" = "Ubuntu" -a "$lsbReleaseInstalled" != "" ]; then  # use /etc/lsb-release for Ubuntu, unless lsb-release package not found (maybe installing it earlier ran into trouble)
      cat /etc/lsb-release | tee -a $diagReportFile
#  elif [ "$platform" = "VM" -o "$OS" = "Debian" ]; then
   else   # else includes Debian, VM platform, or anything else
      cat /etc/os-release | tee -a $diagReportFile
   fi

   echo "Kernel Version: $kernel_version" | tee -a $diagReportFile

	echo | tee -a $diagReportFile
	echo "EdgeStream and SigSRF Install Path and Options Check" | tee -a $diagReportFile
	echo "Install path: $installPath" | tee -a $diagReportFile
	echo "Install options: $installOptions" | tee -a $diagReportFile

	if [ "$installOptions" = "coCPU" ]; then

		# Driver check

		echo "SigSRF coCPU Driver Check" | tee -a $diagReportFile

		libfile="sig_mc_hw"; libname="sig_mc_hw";
		if [ -c /dev/$libfile ]; then
			printf "%s %s[ OK ]\n" $libname "${line:${#libname}}" | tee -a $diagReportFile
		else
			printf "%s %s[ X ]\n" $libname "${line:${#libname}}" | tee -a $diagReportFile
		fi
 	fi

	# Symlinks check

	echo | tee -a $diagReportFile
	echo "EdgeStream and SigSRF Symlinks Check" | tee -a $diagReportFile

	d="Signalogic Symlink"
	if [ -L $installPath/Signalogic ]; then
		printf "%s %s[ OK ]\n" "$d" "${line:${#d}}" | tee -a $diagReportFile
	else
		printf "%s %s[ X ]\n" "$d" "${line:${#d}}" | tee -a $diagReportFile
	fi

	d="Apps Symlink"
	if [ -L $installPath/Signalogic/apps ]; then
		printf "%s %s[ OK ]\n" "$d" "${line:${#d}}" | tee -a $diagReportFile
	else
		printf "%s %s[ X ]\n" "$d" "${line:${#d}}" | tee -a $diagReportFile
	fi

	d="Linux Symlink"
	if [ -L /usr/src/linux ]; then
		printf "%s %s[ OK ]\n" "$d" "${line:${#d}}" | tee -a $diagReportFile
	else
		printf "%s %s[ X ]\n" "$d" "${line:${#d}}" | tee -a $diagReportFile
	fi

	# Libs check

	echo | tee -a $diagReportFile
	echo "SigSRF Libs Check" | tee -a $diagReportFile

	libfile="libhwlib.so"; libname="hwlib"; diagLibPrint;
	libfile="libpktlib.so"; libname="pktlib"; diagLibPrint;
	libfile="libvoplib.so"; libname="voplib"; diagLibPrint;
	libfile="libstreamlib.so"; libname="streamlib";	diagLibPrint;
	libfile="libdiaglib.so"; libname="diaglib"; diagLibPrint;
	libfile="libhwmgr.a"; libname="hwmgr"; diagLibPrint;
	libfile="libfilelib.a"; libname="filelib"; diagLibPrint;
	libfile="libcimlib.a"; libname="cimlib"; diagLibPrint;

	# Apps check

	echo | tee -a $diagReportFile
	echo "EdgeStream Apps Check" | tee -a $diagReportFile

	if [ "$installOptions" = "coCPU" ]; then

		appfile="memTest"; appname="memTest"; diagAppPrint;
		appfile="boardTest"; appname="boardTest"; diagAppPrint;
		appfile="fftTest"; appname="fftTest"; diagAppPrint;
		appfile="streamTest"; appname="streamTest"; diagAppPrint;
	fi

	appfile="iaTest"; appname="iaTest"; diagAppPrint;
	appfile="mediaTest"; appname="mediaTest"; diagAppPrint;
	appfile="mediaTest/hello_codec"; appname="hello_codec"; diagAppPrint;
	appfile="mediaTest/mediaMin"; appname="mediaMin"; diagAppPrint;

	# Leftover /dev/shm hwlib files check

	echo | tee -a $diagReportFile
	echo "DirectCore Residual Files Check" | tee -a $diagReportFile
	d="hwlib_mutex"

	if [ -f /dev/shm/$d ]; then
		printf "%s %s[ X ]\n" $d "${line:${#d}}" | tee -a $diagReportFile  # change polarity -- no leftover files is Ok, leftover is not, JHB Jan2021
	else
		printf "%s %s[ OK ]\n" $d "${line:${#d}}" | tee -a $diagReportFile
	fi

	d="hwlib_info"
	if [ -f /dev/shm/$d ]; then
		printf "%s %s[ X ]\n" $d "${line:${#d}}" | tee -a $diagReportFile
	else
		printf "%s %s[ OK ]\n" $d "${line:${#d}}" | tee -a $diagReportFile
	fi
}

# *********** script entry point ************

# see if user gave noprompt or noprompts on the cmd line, if so set noprompts var

CmdLineArg1="$(echo $1 | tr '[:upper:]' '[:lower:]')"
# uncomment for noprompt debug
# echo "$1 var = $1"
# echo "cmd line var = $CmdLineArg1"
if [ "$CmdLineArg1" = "noprompts" -o "$CmdLineArg1" = "noprompt" -o "$CmdLineArg1" = "-noprompts" -o "$CmdLineArg1" = "-noprompt" ]; then
  noprompts=1
else
  unset noprompts  # make noprompts empty
fi

# initialize global vars, including OS distribution name and kernel version

startPath=$PWD
OS=$(cat /etc/os-release | grep -w NAME=* | sed -n -e '/NAME/ s/.*\= *//p' | sed 's/"//g')  # OS var is used throughout script
if [ -z "$OS" ]; then
  OS=$(cat /etc/centos-release | grep -w CentOS* | sed 's/ .*//')  # CentOS before 7 seems to not have /cat/os-release folder. Add any other OS releases here, keep checking for $OS empty, JHB Apr 2025
fi
kernel_version=`uname -r`
echo "OS distro: $OS, kernel version: $kernel_version"
echo
PS3="Please select platform for SigSRF and EdgeStream software install [1-2]: "

if [ -z "$noprompts" ]; then  # prompt for platform type if noprompts empty

   select platform in "Host" "VM" 
   do
	   case $platform in
		   "Host") break;;
		   "VM") break;;
         *) echo invalid option $platform;;
	   esac
   done
else
   platform="Host"  # otherwise default to Host platform
fi

echo "*********************************************************************"

COLUMNS=1  # force single column menu, JHB Jan2021
PS3="Please select install operation to perform [1-6]: "

   if [ -z "$noprompts" ]; then  # prompt for install type if noprompts empty

      echo

      select opt in "Install SigSRF and EdgeStream Software" "Install SigSRF and EdgeStream Software with ASR Option" "Install SigSRF and EdgeStream Software with coCPU Option" "Uninstall SigSRF and EdgeStream Software" "Check / Verify SigSRF and EdgeStream Software Install" "Exit"

      do
         case $opt in
            "Install SigSRF and EdgeStream Software") if ! packageSetup; then
               if ! unrarCheck; then
		   	      swInstallSetup; dependencyCheck; swInstall;
		         fi
   	      fi
	         break;;

	         "Install SigSRF and EdgeStream Software with ASR Option") installOptions="ASR"; if ! packageSetup; then
		         if ! unrarCheck; then
			         swInstallSetup; dependencyCheck; swInstall;
		         fi
   	      fi
	         break;;

	         "Install SigSRF and EdgeStream Software with coCPU Option") installOptions="coCPU"; if ! packageSetup; then
		         if ! unrarCheck; then
			         swInstallSetup; dependencyCheck; swInstall;
   		      fi
	         fi
	         break;;

	         "Uninstall SigSRF and EdgeStream Software") unInstall; break;;

      	   "Check / Verify SigSRF and EdgeStream Software Install") installCheckVerify; break;;

   	      "Exit") echo "Exiting..."; break;;

            *) echo invalid option $opt;;
         esac
      done

   else  # otherwise default to SigSRF and Edgestream install (note -- can't figure out yet how to modify select-do to force first option, so code below is a repeat for now)

      opt="Install SigSRF and EdgeStream Software"
      if ! packageSetup; then
         if ! unrarCheck; then
		      swInstallSetup; dependencyCheck; swInstall;
		   fi
      fi
    fi
