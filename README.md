alutools
===========

	Alcatel-Lucent Serice-Router tool-set 

alusearch
=============
	alusearch is small tool that search your ALU network for Ports / Services that service-name/description is matching 
        regular expression .

	alusearch creates two raports in csv format / per router
		- .ports - file consist all Ports that description is matching regexp
		Format: Port;ifDescr;ifAlias;Type

		- .svc -  ALU Services that service-name or description matches regexp
		Format: srvid;servicetype;sap;sdp;servicelongname;serviceshortname

	Params:
		-r - Search all routers from file - file format "hostname;community"
		-n - Search on single router
		-C - SNMP Community
	        -m - Search for regexp ( eg. -m 'ZUPA' ) - without -m - match all
		-s - search only for services  /-p for ports
	 

alusearch Examples
====================
		./alusearch.pl -r ./rtrs -m 'ZUPA' - search for string "ZUPA" in ports descriptions / services-names 
                and descriptions ( "ZUPA" is for example large client name ) 
	
		./alusearch.pl -n R1 -C alupass -m 'ZUPA' - the same but only for single routers 'R1'

		./alusearch.pl -r ./rtrs -m 'KAKA' -p - search only for ports matching 'KAKA' we don't care about services 
		names/descriptions

Tested
============
7750 SR7/SR12:
	TiMOS-C-8.0.R6
        TiMOS-C-11.0.R2

5210 SAS-M:
	TiMOS-B-3.0.R10
	TiMOS-B-4.0.R7
	TiMOS-B-5.0.R7
	

AUTHOR
==========
Piotr Chytla pch < at > packetconsulting.pl
