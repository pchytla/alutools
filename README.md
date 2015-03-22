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

isisdiscovery  
=================
 	Intermediate System to Intermediate System (IS-IS) routing protoocol discovery (isisdiscovery) creates topology graph based 
	on ISIS adjacency. It walk by all your ALU switches / routers with active ISIS and discovers networks connections.

**Step by step**
	* 1) Resolve start node to IP
	* 2) Push start node to QUEUE
	* 2) ON node:
		* if QUEUE is empty then exit loop
		* pops node from QUEUE
		* find node SNMP community 
		* gets all neighoring systems , push to @cur_hosts
		* For all nodes in @cur_hosts gets metric from isis route table ( route do start node IP /32 )
		* Sort QUEUE based on metric
		* goto 2:
	* 4) Dump network topology to network.json
	* 5) Convert json to graphml 
		   ./jsont_to_graphml network.json > network.graphml - json_to_graphml moves IP/Netmask/Interface names to graphml edge attributes 
	* 6) Visualize graphml with Guess or cytoscape
	
	[Guess](http://graphexploration.cond.org/) 
			- Layout /  GEM 
			- Display / Information Window - node/edge attributes
			- Guess can't display more then 1 connection between 2 nodes
	[cytoscape](http://cytoscape.org/)
			- Layout - Prefuse Force Directed Layout
			- node/edge attributes in table panel
			

community file
===============
Community file is list of possible snmp communites that can be found in network .
For example if you are using some random string as  community per one device you must add all devices to community file - exact matching
Also matching based on regular expresion :
	-  All switches that name is matching  sw\S.bar have community 'community5' 
	-  all routers that name is matching rtr\S+.foo have comminity 'community4' 
	-  '-C' option can also be single snmp community as string

**Example:** 
node1;community1  
node2;community2  
node3;community3  
rtr\S+\.foo;community4  
sw\S+\.bar;commnity5 

geofile
====================
In default isisdiscovery uses route metric  for sorting. With -g options sorting use  distance between start node and node in queue
REGEX extracts data for matching :

		-  full hostname 
	        -  cities names 
		-  country 

**Format:**  
REGEX : [perl regular expession]  
FOO;[longitude wgs84];[latitude wgs84]  


**Example:**
REGEX : \.(\w{4})$  
FOO;26.1444108980615;60.133457029194  
BAR;19.2045975882404;80.0811616912229  

isisdiscovery examples
======================
	./examples/ directory

Tested
============
7750 SR7/SR12:
	TiMOS-C-8.0.R6
        TiMOS-C-11.0.R2

7210 SAS-M:
	TiMOS-B-3.0.R10
	TiMOS-B-4.0.R7
	TiMOS-B-5.0.R7

7210 SAS-D:
	TiMOS-B-4.0.R7

AUTHOR
==========
Piotr Chytla pch < at > packetconsulting.pl
