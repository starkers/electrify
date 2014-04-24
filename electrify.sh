#!/usr/bin/env bash
#david@starkers.org 140312
#ubuntu 13.10, test on others
#run the script in steps on a clean server, no step7 I know.. much cleaning up to be done

CONF=/etc/electrum.conf


err(){
echo woopsie ; exit
}

gotroot(){
	ME="$(whoami)"
	if [ ! "X$ME" == "Xroot" ]; then
			echo "This step requires root" ; err
	fi
}


step1(){
	gotroot
	useradd -s /bin/bash -m bitcoin || err
	apt-get install -y locales make g++ libboost-all-dev libssl-dev libdb++-dev git wget || err
	dpkg-reconfigure locales
}

step2(){
##su - bitcoin and continue
#su - bitcoin || err
	mkdir -p ~/bin ~/src 
	if ! grep -q 'PATH="$HOME/bin:$PATH' ~/.bashrc ; then
		echo 'PATH="$HOME/bin:$PATH"' >> ~/.bashrc
		. ~/.bashrc
	fi

	mkdir -p ~/src/electrum
	cd ~/src/electrum || err
	git clone https://github.com/spesmilo/electrum-server.git server || err
	chmod +x ~/src/electrum/server/server.py
	ln -s ~/src/electrum/server/server.py ~/bin/electrum-server

	cd ~/src && wget -c http://sourceforge.net/projects/bitcoin/files/Bitcoin/bitcoin-0.8.6/bitcoin-0.8.6-linux.tar.gz || err
	tar xfz bitcoin-0.8.6-linux.tar.gz || err
	cd bitcoin-0.8.6-linux/src/src
	make -j 4 USE_UPNP= -f makefile.unix || err
	strip ~/src/bitcoin-0.8.6-linux/src/src/bitcoind
	ln -s ~/src/bitcoin-0.8.6-linux/src/src/bitcoind ~/bin/bitcoind
}


step4(){
	RPC_USER="$( < /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-32};echo;)"
	RPC_PASS="$( < /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-32};echo;)"
	if [ ! -f "$HOME/.bitcoin/bitcoin.conf" ]; then
			echo "Generating a basic bitcoin.conf"
			mkdir -p "$HOME/.bitcoin"
			cat >> "$HOME/.bitcoin/bitcoin.conf" <<-EOF
			rpcuser=$RPC_USER
			rpcpassword=$RPC_PASS
			daemon=1
			maxconnections=4
			txindex=1
			#rpcssl=1
			EOF
	fi

	## Is bitcoin running
	bitcoind getinfo 1>&2>/dev/null || running=0

	if [ "X$running" == "X0" ]; then
			while true; do
				read -p "Do you wish to start bitcoin daemon? " yn
				case $yn in
					[Yy]* ) bitcoind -deamon ; break;;
					[Nn]* ) echo "Exiting, please start the daemon and run this step again" ; exit;;
					* ) echo "Please answer yes or no.";;
				esac
			done
		else
			echo "Looks like bitcoin is running, good.. don't forget -reindex if this is an old instance"
	fi
}

step5(){
	gotroot
	apt-get install python-setuptools -y  || try_pip=1
	if [ "X$try_pip" == X1 ]; then
			echo "Looks like you don't have easy_install, trying to install pip"
			apt-get install python-pip -y || err
			pip install jsonrpclib || err
		else
			echo "tryig to install jsonrpclib with easy_install"
			easy_install jsonrpclib || err
			#Good lets try plyvel now
			#ubuntu 13.10 requires: libleveldb-dev
			apt-get install libleveldb-dev -y || err
			easy_install plyvel || err
			
	fi
	apt-get install python-openssl -y || err
}

step6(){
	gotroot
	apt-get install python-leveldb -y || err
}



step8(){
	gotroot
	if [ ! -f "$CONF" ]; then
			read -p "It looks like you don't have a config file shall we generate one? " yn
			case $yn in
				[Yy]* )
					ELEC_PASS="$( < /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-32};echo;)"
					RPC_PASS="$(grep ^rpcpassword ~bitcoin/.bitcoin/bitcoin.conf | awk -F\= '{print $2}' | tail -1)"
					RPC_USER="$(grep ^rpcuser ~bitcoin/.bitcoin/bitcoin.conf | awk -F\= '{print $2}' | tail -1)"
					cat ~bitcoin/src/electrum/server/electrum.conf.sample > /etc/electrum.conf || err
					#TODO, echo evaluate these  "ELEC_PASS=$ELEC_PASS; RPC_PASS=$RPC_PASS; RPC_USER=$RPC_USER"
					sed -i "s+= user$+= $RPC_USER+g" "$CONF"
					sed -i "s+= password$+= $RPC_PASS+g" "$CONF"
					sed -i "s+secret$+$ELEC_PASS+g" "$CONF"
					read -p "Please specify the (full) path for the leveldb DB to be installed? [ /home/bitcoin/db ] " DB
					
					if [ "X$DB" == "" ]; then
							echo "Using the default = $DB"
						else
							export DB=/home/bitcoin/db
					fi
					sed -i "s+/path/to/your/database+$DB+g" "$CONF"
					echo "Done, I'd highly recommend checking /etc/electrum.conf manually now"
				;;

				[Nn]* ) exit;;
				* ) echo "Please answer yes or no." ; exit;;
			esac
	fi

	export DB="$(grep "^path_fulltree =" "$CONF" | cut -d "=" -f 2 | awk '{print $1}' | tail -1)"

	if ! [ "$DB" ]; then
			echo "Please set fix the path_fulltree in :$CONF" ; err
	fi
	if [ ! -d "$DB" ]; then
			echo "Creating dir : $DB"
			mkdir -p "$DB" || err
			read -p "Shall I download the DB from the foundry? " yn
			case $yn in
				[Yy]* ) 
					mkdir -p "$DB" || err
					cd "$DB" || err
					( wget -O - "http://foundry.electrum.org/leveldb-dump/electrum-fulltree-10000-latest.tar.gz" | tar --extract --gunzip --strip-components 1 --directory "$DB" --file - ) || err
					chown -R bitcoin:bitcoin "$DB" ||err
					chmod -R  u+rwx,g+rx,g-w,o-rwx  "$DB" #just 'cause I'm oldskool
				;;

				[Nn]* ) exit;;
				* ) echo "Please answer yes or no."; exit 1;;
			esac
	fi
}



step9(){
	cd ~bitcoin
	BIT=2048
	DAYS=730

	tilt(){
	echo "There has been an error, I will not overwrite $1"
	exit 1
	}

	DOMAIN="$(hostname -f)"
	COUNTRY=""
	STATE=""
	LOCALITY=""
	ORGANISATION="Not often but well"
	DEPARTMENT="das blinken lights"

	shopt -q

	echo "-=[ Starting with the required quesions.. ]=-"

	unset INPUT
	echo "Domain: what domain are we making a CSR for? -blank for [$DOMAIN]?"
	read INPUT
	if [ ! "$INPUT" == "" ]; then
			DOMAIN="$INPUT"
	fi
	FQDN="$DOMAIN"

	unset INPUT
	echo "Common Name: what will the FQDN for the live site be?  -blank for ["$DOMAIN"]"
	read INPUT
	if [ ! "$INPUT" == "" ]; then
			FQDN="$INPUT"
	fi

	unset INPUT
	EMAIL="hostmaster@$DOMAIN" 
	echo "email address?: -blank for ["$EMAIL"]"
	read INPUT
	if [ ! "$INPUT" == "" ]; then
			EMAIL="$INPUT"
	fi

	unset INPUT
	echo "Country Name (2 letter code): Leave blank for ["$COUNTRY"]"
	read INPUT
	if [ ! "$INPUT" == "" ]; then
			COUNTRY="$INPUT"
	fi

	unset INPUT
	echo "State/province: leave blank for ["$STATE"]"
	read INPUT
	if [ ! "$INPUT" == "" ]; then
			STATE="$INPUT"
	fi

	unset INPUT
	echo "Locality/city: leave blank for ["$LOCALITY"]"
	read INPUT
	if [ ! "$INPUT" == "" ]; then
			LOCALITY="$INPUT"
	fi

	unset INPUT
	echo "Organisation Name: leave blank for ["$ORGANISATION"]"
	read INPUT
	if [ ! "$INPUT" == "" ]; then
			ORGANISATION="$INPUT"
	fi

	unset INPUT
	echo "Organisation Unit: IE Department name.. leave blank for ["$DEPARTMENT"]"
#This is normally blank"
	read INPUT
	if [ ! "$INPUT" == "" ]; then
			DEPARTMENT="$INPUT"
	fi



	echo "-=[ Please confirm this is correct:... ]=-"
	echo
	cat <<-PFF
	domain requested:                                   $DOMAIN
	Country Name (2 letter code) [US]:                  $COUNTRY
	State or Province Name (full name) [Some-State]:    $STATE
	Locality Name (eg, city) []:                        $LOCALITY
	Organization Name (eg, company):                    $ORGANISATION
	Organizational Unit Name (eg, section) []:          $DEPARTMENT
	Common Name (eg, YOUR name) []:                     $FQDN
	Email Address []:                                   $EMAIL
	An optional company name []:                        
	PFF
	read -p  "-=[  ^c to cancel, [enter] to continue  ]=-" confirm

	if [ -f "server.key" ]; then tilt "server.key" ; fi
	echo "-=[ Generating server.key ]=-"
#openssl genrsa -out server.key $BIT
	openssl genrsa -des3 -passout pass:x -out server.pass.key 2048
	openssl rsa -passin pass:x -in server.pass.key -out server.key
	rm server.pass.key

	if [ -f "server.crt" ]; then tilt "server.crt" ; fi
	echo "-=[ Generating server.crt ]=-"

	openssl req -new -key server.key -out server.csr <<-PFF
	$COUNTRY
	$STATE
	$LOCALITY
	$ORGANISATION
	$DEPARTMENT
	$FQDN
	$EMAIL



	PFF

	echo "Signing the cert"
	openssl x509 -req -days $DAYS -in server.csr -signkey server.key -out server.crt || err

	#handy to keep a record of these IMO
	cat >>server.strings<<-PFF
	$COUNTRY
	$STATE
	$LOCALITY
	$ORGANISATION
	$DEPARTMENT
	$FQDN
	$EMAIL
	PFF
	chown bitcoin:bitcoin server.*
	chmod 0640 server.*
	
	#Set the patch in $CONF
	sed -i "s+/path/to/electrum-+/home/bitcoin/+g" "$CONF"
	#enable ssl
	sed -i "s+^#ssl_+ssl_+g" "$CONF"
	#uncomment them all? dunno
	sed -i "s+^#stratum_tcp_ssl_port+stratum_tcp_ssl_port+g" "$CONF"
	sed -i "s+^#stratum_http_ssl_port+stratum_http_ssl_port+g" "$CONF"

	# sed -i "s+^#report_stratum_tcp_ssl_port+report_stratum_tcp_ssl_port+g" "$CONF"
	# sed -i "s+^#report_stratum_tcp_ssl_port+report_stratum_tcp_ssl_port+g" "$CONF"
	# sed -i "s+^#report_stratum_http_ssl_port+report_stratum_http_ssl_port+g" "$CONF"

}

#load for all steps
. ~/.bashrc
case $1 in
step1)
  step1
  ;;
step2)
  step2
  ;;
step3)
  step3
  ;;
step3)
  step3
  ;;
step4)
  step4
  ;;
step5)
  step5
  ;;
step6)
  step6
  ;;
step7)
  step7
  ;;
step8)
  step8
  ;;
step9)
  step9
  ;;
*)
  echo "Usage: $@ step1 (as root), or: $@ step2 (as bitcoin user)"
  ;;
esac


#######FOO
