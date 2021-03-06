# $Id: sonde-if-snmp32.pl,v 1.1.1.1 2008/06/13 08:55:51 pda Exp $
#
#
# ###################################################################
# boggia : Creation : 27/03/08
#
# fonctions qui permettent de r�cup�rer en SNMP les compteurs de 
# trafic 32 bits
#

sub ifNom_counter32
{
    my ($base,$host,$community,$if,$sonde,$periodicity) = @_;
	
    my $r ;

    if(! $community)
    {
	writelog("ifNom_counter32",$config{syslog_facility},"info",
                        "\t -> ERROR: ($host,$if), Pas de communaute SNMP");
    }
    else
    {
	#cherche si trafic inverse sur l'interface ou pas
	my $inverse = 0;
	if($if =~m/^-/)
	{
        	$inverse = 1;
        	$if =~s/^-//;
	}
        
	# Param�trage des requ�tes SNMP
       	my ($snmp, $error) = Net::SNMP->session(
        	-hostname   => $host,
        	-community   => $community,
       		-port      => 161,
       		-timeout   => $config{"snmp_timeout"},
		-retries        => 2,
      		-nonblocking   => 0x1, 
		-version	=> "2c" );
        
	if (!defined($snmp)) 
	{
		writelog("get_if_snmp32",$config{syslog_facility},"info",
			"\t -> ERROR: SNMP connect error: ($host,$community,$if), $error");
        }
	else
	{
	    #pour compatibilite avec conf basees sur l'index
	    if($if !~m/[a-zA-Z]/)
	    {
        	#conf avec index
        	#print "conf avec index\n";
		chomp $if;
		
		my $oidin = "1.3.6.1.2.1.2.2.1.10.$if";
		my $oidout = "1.3.6.1.2.1.2.2.1.16.$if";
		my $result = $snmp->get_request(
                	-varbindlist   => [$oidin, $oidout],
                	-callback   => [ \&get_if_octet,$base,$host,$if,$oidin,$oidout,$inverse,2,$community,$periodicity] );

	    }
	    #sinon, recherche de l'index par rapport au nom de l'interface
	    else
	    {
		my $trouve_inter = 0;
		my $ligne = "";
		my $index_interface = "";

		# on recherche l'interface dans le fichier nom<=>index	
		my $t_liste_if32 = @liste_if32;
	
		for($i=0;$i<$t_liste_if32;$i++)
		{
			if($liste_if32[$i] !~/^#/ && $liste_if32[$i] !~/^\s*$/)
			{
	                	chomp $liste_if32[$i];
	                        (my $ip, my $inter, my $ind) = split(/;/,$liste_if32[$i]);
  
	                      	#si l'interface recherchee est trouvee
	                       	#on remplit la variable index
	                    	if($inter eq $if && $ip eq $host && $ind ne "")
	                        {
                        		$trouve_inter = 1;
                        	      	$index_interface = $ind;
					$i = $t_liste_if32;
        	                       	#print "\non trouve l'interface $index_interface\n";
 	                     	}
	               }
			

		}
	
		my $ok_interro = 0;
		# si l'interface est pr�sente dans le fichier nom<=>index,
		# controle de coh�rence de l'index par rapport au nom 
		if($trouve_inter == 1)
		{
			#ifMib, description
			my $oid = "1.3.6.1.2.1.2.2.1.2.$index_interface";
			$r = $snmp->get_request(
				-varbindlist   => [$oid],
				-callback   => [ \&get_if32_name, $base,$host,$community,$if,$oid,$index_interface,$inverse,$periodicity] );

		}
		# sinon, il faut rechercher l'index de l'interface et remplir le fichier nom<=>idex
		else
		{
			my @desc_inter=();
			# cherche liste des interfaces
			$param = $community."@".$host;
			&snmpmapOID("desc","1.3.6.1.2.1.2.2.1.2");
	        	@desc_inter = &snmpwalk($param, "desc");

        		$nb_desc = @desc_inter;

			if($desc_inter[0] ne "")
			{
				$index_interface = "";

				my $i;	
		        	for($i=0;$i<$nb_desc;$i++)
 	 		      	{
   	        		     	if($desc_inter[$i]=~m/$if/)
	                		{
	                		       	#print "$desc_inter[$i]\n";
						chomp $desc_inter[$i];
       		                 		$index_interface = (split(/:/,$desc_inter[$i]))[0];
        		        	#       print "index = $index_interface\n";
	                	        	$i = $nb_desc;
                        			$ok_interro = 1;
	                		}
	        		}

				# on trouve l'interface a la suite du snmpwalk
				# on remplit le fichier nom<=>index et on iterroge l'equipement
				if($ok_interro == 1)
	        		{
        	        		if($lock_liste_if32 == 0)
                			{
						$lock_liste_if32 = 1;
		
						$ligne = "$host;$if;$index_interface";
						push @liste_if32,$ligne;
	
						$maj_if32_file = 1;				
						$lock_liste_if32 = 0;	
					}
				
					my $oidin = "1.3.6.1.2.1.2.2.1.10.$index_interface";
                			my $oidout = "1.3.6.1.2.1.2.2.1.16.$index_interface";
                			$r = $snmp->get_request(
                        			-varbindlist   => [$oidin, $oidout],
                        			-callback   => [ \&get_if_octet,$base,$host,$if,$oidin,$oidout,$inverse,2,$community,$periodicity] );
				}
				else
				{
					writelog("get_if_snmp32",$config{syslog_facility},"info",
						"\t -> ERROR: interface $if inexistante sur $host");
				}
			}
			else
			{
				writelog("get_if_snmp32",$config{syslog_facility},"info",
					"\t -> ERROR: $community\@$host ne r�pond pas");
			}
		}
	    }
	}
    }
}


sub get_if32_name 
{
	my ($session,$base,$host,$community,$if,$oid,$id_if,$inverse,$periodicity) = @_;	

	my $result;
	my $ok_interro;

	my ($snmp, $error) = Net::SNMP->session(
        	-hostname   => $host,
        	-community   => $community,
	        -port      => 161,
	        -timeout   => $config{"snmp_timeout"},
		-retries        => 2,
	        -nonblocking   => 0x1,
		-version        => "2c" );

	my $r;
	my $err=0;

	if (!defined($session->var_bind_list)) 
	{
       		my $error  = $session->error;

		writelog("get_if_snmp32",$config{syslog_facility},"info",
			"\t -> ERROR: get_if_name($host) Error: $error");
		
		$err=1;
    	} 
	else 
	{
       		$result = $session->var_bind_list->{$oid};
       		#print "get_if_name($host) $oid = $result\n";
    	}

	if($result=~m/$if/ && $err==0)
        #si le nom de l'interface a toujours le meme index
        {
                $ok_interro = 1;
                #print "\nL'interface trouvee correspond a son index reel\n";
        }
        elsif($err == 0)
        {
                $ok_interro = 0;
               
		writelog("get_if_snmp32",$config{syslog_facility},"info",
                	"\t -> ERROR: L'interface trouvee ne correspond pas a son index reel");
		
		# cherche liste des interfaces
                my $param = $community."@".$host;
                &snmpmapOID("desc","1.3.6.1.2.1.2.2.1.2");
                my @desc_inter = &snmpwalk($param, "desc");

                my $nb_desc = @desc_inter;

                my $index_interface = "";
	
		my $i;
                for($i=0;$i<$nb_desc;$i++)
                {
                        if($desc_inter[$i]=~m/$if/)
                        {
                                #print "$desc_inter[$i]\n";
                                chomp $desc_inter[$i];
                                $index_interface = (split(/:/,$desc_inter[$i]))[0];
                                #       print "index = $index_interface\n";
                                $i = $nb_desc;
                                $ok_interro = 1;
                        }
                }

		if($ok_interro == 1)
		{
			#print "tentative de correction\n";
			if($lock_liste_if32 == 0)
                        {
	                        $lock_liste_if32 = 1;
				my $t_liste_if32 = @liste_if32;
				
				my $i;
				for($i=0;$i<$t_liste_if32;$i++)
				{
					(my $ip, my $inter, my $ind) = split(/;/,$liste_if32[$i]);
					if($ip eq $host && $if eq $inter)
					{
						$liste_if32[$i] = "$ip;$if;$index_interface";
					}	
				}
				$lock_liste_if32 = 0;
				$maj_if32_file = 1;
			}
			else
			{
				writelog("get_if_snmp32",$config{syslog_facility},"info",
					"\t -> ERROR: Fichier if32.txt lock�. Pas de mise � jour");
			}
			$id_if = $index_interface;
		}
		else
		{
			writelog("get_if_snmp32",$config{syslog_facility},"info",
				"\t -> ERROR: interface $if inexistante sur $host. Pas de mise � jour.");
		}
        }

	if($id_if ne "" && $ok_interro ==1)
	{
		my $oidin = "1.3.6.1.2.1.2.2.1.10.$id_if";
                my $oidout = "1.3.6.1.2.1.2.2.1.16.$id_if";

                $r = $snmp->get_request(
                	-varbindlist   => [$oidin, $oidout],
                	-callback   => [ \&get_if_octet,$base,$host,$if,$oidin,$oidout,$inverse,2,$community,$periodicity] );
	}
}

return 1;
