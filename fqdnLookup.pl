#!/usr/bin/perl
# fqdnLookup.pl


use strict;
use warnings;
my ($dir,$confFH,$confFile,$zone, $zoneFile,$answer,$name,$type,$pool,$member,$server,$memberVS,$vs,$wideip,$wipPool,$aType,$wipName,$poolMember,$printBuffer,$gtmFile,$ltmFile,$desc,$ip,$virtualName,$addr,$outputFD);
my (%zones,%gtmConfigs,%wips,%pools,%vses,%ips,%ltmConfigs);
my $zonefilePath = "configs/zonefiles/";
my $gtmfilePath = "configs/gtm/";
my $ltmfilePath = "configs/ltm/";
my $outputPath = "outputs/";

&readZonefiles;
&readGTMConfig;
&assembleGTMobjects;
&readLTMConfig;
&getVipFqdnInfo;
&csv_Output;

########### Subroutines ##############

# get A and CNAME records from zonefiles
sub readZonefiles {
  opendir my $dir, $zonefilePath or die "Cannot open directory: $!";
  my @files = readdir $dir;
  foreach my $file (@files) {
    next if ($file eq ".") || ($file eq "..");

    # open zonefile
    $zoneFile = $zonefilePath . $file;
    open($confFH, $zoneFile) || die "Unable to open $zoneFile: $!\n";
    while (<$confFH>) {
        chomp();
        $_ =~ s/[\r\n]$//;
        $_ =~ s/\s+$//;
    
      if (/^;  Database file \(null\) for (.*) zone\./) {
        $zone = lc $1;
        print "# Reading zone info for $zone\n";
      }
      # get A and CNAME records
      if (/^(?:(\S+)|)(?:\s+|\t+)(?:\[\S+\](?:\s+|\t+)|)(?:\S+(?:\s+|\t+|)|)(A|CNAME)(?:\s+|\t+)(\S+)/) {
        $name = lc $1 if ($1);
        $type = $2;
        $answer = lc $3;
        $name =~ s/\.$//;
        $answer =~ s/\.$//;
        $zones{$zone}{$type}{$answer}{names}{$name}{name} = $name;
        $zones{$zone}{$type}{$answer}{names}{$name}{fqdn} = $name . "." . $zone;
      }
    }
  }
  closedir $dir;
}

sub readGTMConfig {
  opendir my $dir, $gtmfilePath or die "Cannot open directory: $!";
  my @files = readdir $dir;
  foreach my $file (@files) {
    next if ($file eq ".") || ($file eq "..");
    $gtmFile = $gtmfilePath . $file;
    open($confFH, $gtmFile) || die "Unable to open $gtmFile: $!\n";
    print "# Reading GTM info from $gtmFile\n";
    while (<$confFH>) {
      chomp();
      $_ =~ s/[\r\n]$//;
      $_ =~ s/\s+$//;
      $_ =~ s/\"//g;

      if (/^gtm pool /../^\}/) {
        if (/^gtm pool (a |aaaa |)(.*) \{/) {
          $type = $1;
          $type = "a" if ($type eq "");
          $pool = $2;
          $type =~ s/\s//;
          $gtmConfigs{$file}{pools}{$type}{pools}{$pool}{type} = $type;
          $gtmConfigs{$file}{pools}{$type}{pools}{$pool}{name} = $pool;
          $gtmConfigs{$file}{pools}{$type}{pools}{$pool}{lbMode} = "round-robin";
          $gtmConfigs{$file}{pools}{$type}{pools}{$pool}{maxAddr} = "1";
        }
        if (/ load\-balancing\-mode (.*)/) {
          $gtmConfigs{$file}{pools}{$type}{pools}{$pool}{lbMode} = $1;
        }
        if (/ max\-address\-returned (\d+)/) {
          $gtmConfigs{$file}{pools}{$type}{pools}{$pool}{maxAddr} = $1;
        }
        if (/\s{8}((.*):(.*)) \{/) {
          $member = $1;
          $server = $2;
          $memberVS = $3;
          $server =~ s/^\s+//;
          $server =~ s/\s+$//;

          $gtmConfigs{$file}{pools}{$type}{pools}{$pool}{members}{$member}{state} = "enabled";
          $gtmConfigs{$file}{pools}{$type}{pools}{$pool}{members}{$member}{server} = $server;
          $gtmConfigs{$file}{pools}{$type}{pools}{$pool}{members}{$member}{memberVS} = $memberVS;
        }
        if (/^\s+disabled/) {
          $gtmConfigs{$file}{pools}{$type}{pools}{$pool}{members}{$member}{state} = "disabled";
        }
        if (/ (?:member-|)order (\d+)/) {
          $gtmConfigs{$file}{pools}{$type}{pools}{$pool}{members}{$member}{order} = $1;
        }
      }
      if (/^gtm server /../^\}/) {
        if (/^gtm server (.*) \{/) {
          $server = $1;
          $server =~ s/^\s+//;
          $server =~ s/\s+$//;
          $gtmConfigs{$file}{vses}{$server}{name} = $server;
        }
        if (/datacenter (.*)/) {
          my $datacenter = $1;
          $gtmConfigs{$file}{vses}{$server}{datacenter} = $datacenter;
        }
        if (/^\s{4}virtual\-servers \{/../^\}/) {
          if ( /^\s{8}(.*) \{$/ && !(/depends-on/)) {
            $vs = $1;
            $vs =~ s/^\s+//;
            $vs =~ s/\s+$//;
          }
          if (/ destination ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+):/ || / destination (([a-fA-F0-9]{1,4}(:{1,2}|))+)\./) {
            $ip = $1;
            $gtmConfigs{$file}{vses}{$server}{vses}{$vs}{intIp} = $ip;
            $gtmConfigs{$file}{ips}{$ip}{intIp} = $ip;
            $gtmConfigs{$file}{ips}{$ip}{datacenter} = $gtmConfigs{$file}{vses}{$server}{datacenter};
            $gtmConfigs{$file}{vses}{$server}{vses}{$vs}{extIp} = "none";
            $gtmConfigs{$file}{ips}{$ip}{extIp} = "none";
          }
          if (/ translation-address ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/) {
            my $intIp = $1;
            $gtmConfigs{$file}{vses}{$server}{vses}{$vs}{intIp} = $intIp;
            $gtmConfigs{$file}{vses}{$server}{vses}{$vs}{extIp} = $ip;
            $gtmConfigs{$file}{ips}{$intIp}{intIp} = $intIp;
            $gtmConfigs{$file}{ips}{$intIp}{datacenter} = $gtmConfigs{$file}{vses}{$server}{datacenter};
            $gtmConfigs{$file}{ips}{$intIp}{extIp} = $ip;
            #print "## $vs - $gtmConfigs{$file}{ips}{$intIp}{intIp} - $gtmConfigs{$file}{ips}{$intIp}{extIp}\n";
          }
        }
      }
      if (/^gtm wideip /../^\}/) {
        if (/^gtm wideip (a |aaaa |)(.*) \{/) {
          $type = $1;
          $type = "a" if ($type eq "");
          $wideip = lc $2;
          $type =~ s/\s//;

          $gtmConfigs{$file}{wips}{$type}{wips}{$wideip}{name} = $wideip;
          $gtmConfigs{$file}{wips}{$type}{wips}{$wideip}{lbMode} = "round-robin";
          @{$gtmConfigs{$file}{wips}{$type}{wips}{$wideip}{ips}} = ();
        }
        if (/ aliases \{/../^\s{4}\}/) {
          if (/^\s{8}(\S+)/) {
            my $alias = $1;
            $alias =~ s/^\s+//;
            $alias =~ s/\s+$//;
            $gtmConfigs{$file}{wips}{$type}{wips}{$wideip}{aliases}{$alias}{alias} = $alias;
          }
        }
        if (/ pool\-lb\-mode (.*)/) {
          $gtmConfigs{$file}{wips}{$type}{wips}{$wideip}{lbMode} = $1;
        }
        if (/ pools \{/../^\s{4}\}/) {
          if ( /\s{8}(.*) \{/ ) {
            $wipPool = $1;
          }
          if ( / order (\d+)/ ) {
            $gtmConfigs{$file}{wips}{$type}{wips}{$wideip}{pools}{$wipPool}{order} = $1;
          }
        }
      }
    }
  }
}

sub assembleGTMobjects {
  foreach my $file (sort keys %gtmConfigs) {
    print "# Assembling GTM info for $file\n";
    foreach $type (sort keys %{$gtmConfigs{$file}{wips}}){
      $aType = $type;
      foreach $wipName (sort keys %{$gtmConfigs{$file}{wips}{$type}{wips}}) {
        $name = $wipName;
        foreach $wipPool (sort keys %{$gtmConfigs{$file}{wips}{$type}{wips}{$wipName}{pools}}){
          foreach $poolMember (sort keys %{$gtmConfigs{$file}{pools}{$type}{pools}{$wipPool}{members}}){
            $server = $gtmConfigs{$file}{pools}{$type}{pools}{$wipPool}{members}{$poolMember}{server};
            $memberVS = $gtmConfigs{$file}{pools}{$type}{pools}{$wipPool}{members}{$poolMember}{memberVS};
            next if !($server);
            chomp($server);
            next if ( grep( /$gtmConfigs{$file}{vses}{$server}{vses}{$memberVS}{intIp}/, @{$gtmConfigs{$file}{wips}{$type}{wips}{$wipName}{ips}} ) );
            next if ( grep( /$gtmConfigs{$file}{vses}{$server}{vses}{$memberVS}{extIp}/, @{$gtmConfigs{$file}{wips}{$type}{wips}{$wipName}{ips}} ) );
            push (@{$gtmConfigs{$file}{wips}{$type}{wips}{$wipName}{ips}}, $gtmConfigs{$file}{vses}{$server}{vses}{$memberVS}{intIp});
            push (@{$gtmConfigs{$file}{wips}{$type}{wips}{$wipName}{ips}}, $gtmConfigs{$file}{vses}{$server}{vses}{$memberVS}{extIp}) if ($gtmConfigs{$file}{vses}{$server}{vses}{$memberVS}{extIp} ne "none");
          }
          if ($gtmConfigs{$file}{wips}{$type}{wips}{$wipName}{pools}{$wipPool}{order} == "0") {
            $gtmConfigs{$file}{wips}{$type}{wips}{$wipName}{mainLBMode} = $gtmConfigs{$file}{pools}{$type}{pools}{$wipPool}{lbMode};
          }
        }
      }
    }
  }
}

# get VS info from LTM configs
sub readLTMConfig {
  opendir my $dir, $ltmfilePath or die "Cannot open directory: $!";
  my @files = readdir $dir;
  foreach my $file (@files) {
    next if ($file eq ".") || ($file eq "..");
    $ltmFile = $ltmfilePath . $file;
    open($confFH, $ltmFile) || die "Unable to open $ltmFile: $!\n";
    print "# Reading LTM info from $ltmFile\n";
    while (<$confFH>) {
      chomp();
      $_ =~ s/[\r\n]$//;
      $_ =~ s/\s+$//;
      $_ =~ s/\"//g;

      # Get virtuals 
      if (/^ltm virtual .* \{/../^\}/) {
        if (/^ltm virtual (?:\/Common\/|)(.*) \{/) {
          $virtualName = $1;
        }
        if (/^\s{3,4}description (?:\"|)(.*)(?:\"|)/) {
          $desc = $1;
          $desc =~ s/[\r\n]$//;
          $desc =~ s/\s+$//;
          $desc =~ s/[\"\,]//g;
        }
        if (/^\s{3,4}destination (?:\/Common\/|)(.*):(.*)/) {
          $addr = $1;
          if (!($ltmConfigs{$file}{virtuals}{$addr})) {
            $ltmConfigs{$file}{virtuals}{$addr}{extIp} = "none";
            @{$ltmConfigs{$file}{virtuals}{$addr}{fqdns}} = ();
            @{$ltmConfigs{$file}{virtuals}{$addr}{wips}} = ();
            @{$ltmConfigs{$file}{virtuals}{$addr}{vsNames}} = ();
            @{$ltmConfigs{$file}{virtuals}{$addr}{ports}} = ();
            @{$ltmConfigs{$file}{virtuals}{$addr}{descriptions}} = ();
          }
          push (@{$ltmConfigs{$file}{virtuals}{$addr}{vsNames}}, $virtualName);
          push (@{$ltmConfigs{$file}{virtuals}{$addr}{ports}}, $2);
          push (@{$ltmConfigs{$file}{virtuals}{$addr}{descriptions}}, $desc) if ($desc);
        }
        if (/^\s{3,4}ip-forward/) {
          $ltmConfigs{$file}{virtuals}{$addr}{isIPForward} = 1;
        }
      }
    }
  }
}

# get FQDN info for each VS
sub getVipFqdnInfo {
  foreach my $file (sort keys %ltmConfigs) {
    print "# Getting fqdn info for VIPs in $file\n";

    foreach $addr (sort keys %{$ltmConfigs{$file}{virtuals}}) {
      next if ($ltmConfigs{$file}{virtuals}{$addr}{isIPForward});
      # check gtm config for VIP addresses
      foreach my $gtmFile (sort keys %gtmConfigs) {
        #print "# $gtmFile - $addr - $gtmConfigs{$gtmFile}{ips}{$addr}{intIp} - $gtmConfigs{$gtmFile}{ips}{$addr}{extIp}\n" if ($gtmConfigs{$gtmFile}{ips}{$addr}{intIp});
        foreach $type (sort keys %{$gtmConfigs{$gtmFile}{wips}}){
          $aType = $type;
          foreach $wipName (sort keys %{$gtmConfigs{$gtmFile}{wips}{$type}{wips}}) {
            foreach my $wipIp (@{$gtmConfigs{$gtmFile}{wips}{$type}{wips}{$wipName}{ips}}) {
              #$gtmConfigs{$file}{ips}{$intIp}{extIp}
              if ($addr eq $wipIp) {
                my $wipFqdn = $wipName . "(wideip)";
                $wipFqdn =~ s/\/common\///;
                $ltmConfigs{$file}{virtuals}{$addr}{extIp} = $gtmConfigs{$gtmFile}{ips}{$addr}{extIp};
                #print "## $gtmFile - $addr - $gtmConfigs{$gtmFile}{ips}{$addr}{intIp} - $gtmConfigs{$gtmFile}{ips}{$addr}{extIp}\n";

                push (@{$ltmConfigs{$file}{virtuals}{$addr}{wips}}, $wipFqdn);
                foreach my $alias (sort keys %{$gtmConfigs{$gtmFile}{wips}{$type}{wips}{$wipName}{aliases}}) {
                  push (@{$ltmConfigs{$file}{virtuals}{$addr}{wips}}, $alias . "(wip-alias)");
                }
              }
            }
          }
        }
        $ltmConfigs{$file}{virtuals}{$addr}{extIp} = $gtmConfigs{$gtmFile}{ips}{$addr}{extIp} if ($gtmConfigs{$gtmFile}{ips}{$addr}{extIp} && $gtmConfigs{$gtmFile}{ips}{$addr}{extIp} ne "none");
      }
      # check zonefiles for VIP address
      foreach $zone (sort keys %zones) {
        foreach $answer (sort keys %{$zones{$zone}{A}}) {
          if ($addr eq $answer || $ltmConfigs{$file}{virtuals}{$addr}{extIp} eq $answer) {
            foreach my $name (sort keys %{$zones{$zone}{A}{$answer}{names}}){
              my $fqdn = $zones{$zone}{A}{$answer}{names}{$name}{fqdn};
              push (@{$ltmConfigs{$file}{virtuals}{$addr}{fqdns}}, $fqdn . "(A)");
              foreach my $cname (sort keys %{$zones{$zone}{CNAME}}) {
                if ($cname eq $fqdn) {
                  foreach my $aname (sort keys %{$zones{$zone}{CNAME}{$cname}{names}}){
                    my $cnameFqdn = $zones{$zone}{CNAME}{$cname}{names}{$aname}{fqdn};
                    push (@{$ltmConfigs{$file}{virtuals}{$addr}{fqdns}}, $cnameFqdn . "(CNAME)");
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

sub csv_Output {
  foreach my $ltmConfFile (sort keys %ltmConfigs) {
    my $ltmName = $ltmConfFile;
    $ltmName =~ s/\.conf$//;

    my $csvFile = $outputPath . $ltmName . ".csv";
    system ("rm -f $csvFile");
    open($outputFD, ">>$csvFile") || die "Unable to open '$csvFile': $!\n";
    print $outputFD "VS Names,IP Address (int), IP Address (ext), VS Ports,fqdns from Zone files,WideIPs from GTM config,VS Descriptions\n";
    foreach $addr (sort keys %{$ltmConfigs{$ltmConfFile}{virtuals}}) {
      next if ($ltmConfigs{$ltmConfFile}{virtuals}{$addr}{isIPForward});

      my $extIp = "none";
      my $zoneFqdns = join("\n",@{$ltmConfigs{$ltmConfFile}{virtuals}{$addr}{fqdns}});
      my $gtmFqdns = join("\n",@{$ltmConfigs{$ltmConfFile}{virtuals}{$addr}{wips}});
      my $vsNames = join("\n",@{$ltmConfigs{$ltmConfFile}{virtuals}{$addr}{vsNames}});
      my $ports = join("\n",@{$ltmConfigs{$ltmConfFile}{virtuals}{$addr}{ports}});
      my $descriptions = join("\n",@{$ltmConfigs{$ltmConfFile}{virtuals}{$addr}{descriptions}});
      $extIp = $ltmConfigs{$ltmConfFile}{virtuals}{$addr}{extIp} if ($ltmConfigs{$ltmConfFile}{virtuals}{$addr}{extIp});

      print $outputFD  "\"$vsNames\",$addr,$extIp,\"$ports\",\"$zoneFqdns\",\"$gtmFqdns\",\"$descriptions\"\n";
    }
    close($outputFD);
    print "# Output of $ltmConfFile is at $csvFile\n";
  }
}
