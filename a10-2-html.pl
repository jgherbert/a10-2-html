#!/usr/local/bin/perl -w
#
# a10-to-html.pl
#
# Purpose: Process A10 load balancer configurations, extract the content
#          and display it in a webpage in a way that pulls together all
#          the VIP information in one place.

use strict;
use HTML::Entities;
use Getopt::Long;

#-------------------------------------------------------
# Set up global variables - edit these as needed
#-------------------------------------------------------

# Where are the configuration files stored? (output from show run all-partitions)
my $configDir = '/data/a10configs';

# What pattern identifies a10 configuration files? (hostname.pattern)
my $a10pattern = '.mydomain.com.a10.txt';

# Where is the HTML page header file located?
my $htmlHeader = './a10header.htm';

#-------------------------------------------------------

# Run the script then exit
exit( main() );

# Fat lady sings

#-------------------------------------------------------
# Here be dragons. Beware all ye who scroll beyond.
#-------------------------------------------------------

sub main {

    # Get command line options
    my %opt;
    GetOptions(
                "p=s" => \$opt{partition},
                "d=s" => \$opt{devicename},
                "m=s" => \$opt{matchstring},
    );

    # Process the header file
    my @htmlHeader;
    if ( open( my $IN, "<", $htmlHeader ) ) {
        @htmlHeader = <$IN>;
        close($IN);
    } else {
        return ( fail("Unable to open HTML header file.") );
    }

    # Get a sorted list of the available config files
    my @devices;
    opendir( my $DIR, $configDir );
    while ( my $file = readdir($DIR) ) {
        if ( $file =~ /^(.+)$a10pattern$/ ) {
            push( @devices, $1 );
        }
    }
    @devices = sort @devices;

    # Loop and process each device
    foreach my $device (@devices) {
        if ( $opt{devicename} ) {
            next if ( $device ne $opt{devicename} );
        }

        my @htmlDeviceCombo;
        if ( !$opt{partition} ) {

       # If partition isn't specified, we need to set up a combo for the devices
       # including selecting the current device by default
            push( @htmlDeviceCombo, <<END);
<div class="headerselector">Change Device: <select class="device">
END
            foreach my $dev (@devices) {
                my $selected = '';
                if ( $dev eq $device ) {
                    $selected = ' selected';
                }
                push( @htmlDeviceCombo, <<END);
<option value="$dev"$selected>$dev</option>
END
            }
            push( @htmlDeviceCombo, <<END);
</select></div>
END
        }

        my $file = $configDir . '/' . $device . $a10pattern;
        my @config;
        my @allconfig;
        if ( ( -e $file ) && ( -r $file ) ) {
            if ( open( my $IN, "<", $file ) ) {

                # Grab all config (I was anyway, so, uh, yeah)
                @allconfig = <$IN>;
            }
        } else {

            # Hmmph. Skip this one I guess.
            warn(
"Warning: unable to read $file. That sucks. Onward and upward.\n" );
            next;
        }

     # Now process the 'full' config in a smart hierarchy for the web page
     # Abuse a hash to store the config in a logical (ish) structure type thingy
        my %hierarchy;
        my @output;
        processConfig(
                       opt        => \%opt,
                       configref  => \@allconfig,
                       hashref    => \%hierarchy,
                       outref     => \@output,
                       device     => $device,
                       comboref   => \@htmlDeviceCombo,
                       htmlHeader => \@htmlHeader
        );
    }    # end foreach device
}    # end main

sub processConfig {
    my %ARGS            = @_;
    my $cref            = $ARGS{configref};
    my $href            = $ARGS{hashref};
    my $outref          = $ARGS{outref};
    my $device          = $ARGS{device};
    my $comboref        = $ARGS{comboref};
    my %opt             = %{ $ARGS{opt} };
    my @htmlHeader      = @{ $ARGS{htmlHeader} };
    my @htmlDeviceCombo = @$comboref;

    # Local array of output, to copy to $outref at the end
    my @output;

    # Copy array locally so we can consume it
    my @conf = @$cref;

    # Temporary local hash to make things easier and shorter to read
    my %h;

    # Track fold id so that every fold has a unique id
    my $fold = 1;

    # Partition restriction; default value
    my $activePartition = 'shared';

    my %allvips;

    # Print the first part of the output (the header)
    print @htmlHeader;

    # Run through the configuration and extract information
    while ( my $line = shift @conf ) {
        chomp($line);

        # We are looking for a few things on the way past in shared partition,
        # e.g. the vrid_snat pools

        if ( $line =~
/^ip nat pool ([\w\d\-\_]+) (\d+\.\d+\.\d+\.\d+) (\d+\.\d+\.\d+\.\d+) netmask \//
          )
        {
            # Example line:
            # ip nat pool vrid1_v106_snat_host1 10.228.117.247 \
            # 10.228.117.247 netmask /32  vrid 1
            my $name  = $1;
            my $start = $2;
            my $end   = $3;
            my $range = $start . ' - ' . $end;
            if ( $start eq $end ) {
                $range = $start . '/32';
            }
            $h{snatpool}{$name} = $range;
        } elsif ( $line =~ /^ip nat pool-group/ ) {

            # Example line:
            # ip nat pool-group vrid1-range1-snat vrid1_range1_host1 \
            # [...] vrid 1

            # Extract list of snat-pools in this group
            my $copy = $line;
            $copy =~ /ip nat pool-group ([\w\d\-\_]+) (.*) vrid \d+/;
            my $name    = $1;
            my $list    = $2;
            my @pools   = split( / /, $list );
            my $natlist = '';
            foreach my $pool (@pools) {
                my $range = $h{snatpool}{$pool};
                $natlist = addLine( $natlist, $range );
            }

# Finally - and this is a lovely cheat - store the nat pool-group as a snatpool
# so we don't have to differentiate between groups and pools when creating output
            $h{snatpool}{$name} = $natlist . '{{END_FOLD}}';
        } elsif ( $line =~ /^health monitor ([\w\d\-\_\.]+)\s?(.*)$/ ) {

            # health monitor tcp-half-63901
            #  method tcp  63901 halfopen
            # !
            my $name   = $1;
            my $params = $2;
            if ( $params ne '' ) {

                # *cough* Insert these entries on the front of the conf array
                if ( $params =~ /interval (\d+)/ ) {
                    unshift( @conf, "interval " . $1 );
                }
                if ( $params =~ /timeout (\d+)/ ) {
                    unshift( @conf, "timeout " . $1 );
                }
            }
            my $hm =
              getSubLines( \@conf, \%h, "health monitor", "default ICMP" );
            $h{hm}{$name} = $hm;
        } elsif ( $line =~ /slb template (.*)$/ ) {
            my $name = $1;
            my $tm = getSubLines( \@conf, \%h, "slb template ", "default" );
            $h{template}{$name} = $tm;
        } elsif ( $line =~ /slb server ([\w\d\-\_\.]+) (\d+\.\d+\.\d+\.\d+)/ ) {
            my $name = $1;
            my $ip   = $2;
            $h{server}{$name} = $ip;
        } elsif ( $line =~ /^slb service-group (.*) (tcp|udp)$/ ) {

            # Example line:
            # slb service-group 1234_thing.mycorp.com-13724 tcp
            # member server1_10.1.8.84:13724
            # member server2_10.2.1.84:13724

            my $name = $1;
            my $type = $2;
            my $sg = getSubLines( \@conf, \%h, "slb service-group ", "empty" );
            $h{sg}{$type}{$name} = $sg;
        } elsif ( $line =~
                  /^slb virtual-server ([\w\d\-\_\.]+) (\d+\.\d+\.\d+\.\d+)$/ )
        {
            # If a matchstring was defined, we should check if it exists within
            # the virtual-server name. Otherwise skip it.
            my $name = $1;
            my $ip   = $2;

            if ( $opt{matchstring} ) {
                my $term = $opt{matchstring};
                next if ( $name !~ /$term/i );
            }

            $h{vs}{$name}{ip} = $ip;

            # We will loop round now and extract the relevant
            # information on the way by (e.g. service-group expansion,
            # snat expansion, template expansion). This is really
            # where the money is, so to speak. We will track the fold id
            # using $fold.

            my $indent  = 0;
            my $vipname = $name;
            my @vipout;    # output just for this vip so we can order them later

            push(
                @vipout,
                indent(
"\n<hr align=\"left\" width=\"75%\">$activePartition: $name - $ip\n",
                    $indent,
                    "pretitle"
                )
            );

            $indent = 3;
            my $protocol = '';

            while ( my $subline = shift(@conf) ) {

                chomp($subline);
                $subline =~ s/^\s+//g;
                last if ( $subline =~ /^!/ );

                if ( $subline =~ /^port\s(\d+)\s+([\w\d\-\_]+)/ ) {
                    ## PORT
                    $protocol = $2;    # good to know if it's UDP
                    if ( $protocol ne "udp" ) {

                        # Good guess, right?
                        $protocol = 'tcp';
                    }
                    $indent = 6;
                    push( @vipout, indent( $subline, $indent, 'presubhead' ) );
                    $indent = 9;
                } elsif ( $subline =~ /^service-group ([\w\d\-\_\.]+)/ ) {
                    ## SERVICE-GROUP
                    my $sg    = $1;
                    my $sgdef = $h{sg}{$protocol}{$sg};
                    $indent = 9;
                    if ( $sgdef =~ /health-check/m ) {

                        # Need to pre-process the health-monitor
                        my @deflines = split( "\n", $sgdef );
                        my $hcout = "";
                        foreach my $defline (@deflines) {
                            if ( $defline =~ /\s*health-check (.*)$/ ) {

                                # Expand the health-check
                                my $hcname = $1;
                                my $hcfold = "";
                                my $hmdef  = $h{hm}{$hcname};
                                if ( $defline =~ /^{{/ ) {
                                    $hcout .= '{{BEGIN_FOLD}}';
                                }
                                $hcfold =
                                  buildFold(
                                             title => 'health-check ' . $hcname,
                                             content => $hmdef,
                                             fold    => $fold++,
                                             indent  => $indent + 3
                                  ) || "";

                                # Remove opening span class
                                # to avoid duplication in
                                # nested content
                                $hcfold =~ s/^<span class="preformatted">\s+//;

                                # Strip out all but 3 spaces
                                # on subsequent lines because
                                # they'll be re-added when
                                # the parent fold is built...
                                $hcfold =~ s/\n\s+/\n   /g;

                                # Check for empty lines (only
                                # spaces) and replace with default
                                # text. Remember: the default
                                # health monitor is ICMP, but
                                # the default for an SG without
                                # a health-check applied would
                                # be to use the protocol level check
                                $hcfold =~
s/\n<span class="preformatted">\s+<\/span>\n/\n<span class="preformatted">               method ICMP<\/span>\n/;

                                # Append the folded health-check
                                # in place of the original line,
                                # and rebuild indent
                                $hcout .=
                                    $hcfold
                                  . "<span class=\"preformatted\">"
                                  . ( " " x ( $indent + 3 ) );
                            } else {

                                # Append the non-HC line back to the SG string
                                $hcout .= $defline . "\n";
                            }
                        }

                        # Swap in the expanded sgdef string
                        $sgdef = $hcout;
                    } else {
                        ## NO HEALTH-CHECK
                        ## No health-check defined, so comment that this uses the default health-check
                        if ( $sgdef =~ /^{{/ ) {
                            $sgdef =~
s/{{BEGIN_FOLD}}/{{BEGIN_FOLD}}(uses default $protocol health-check)\n/;
                        } else {
                            $sgdef =
                              "(uses default $protocol health-check)\n"
                              . $sgdef;
                        }
                    }

                    if ( $sgdef =~ /{{/ ) {

                        # This needs a fold
                        $sgdef =
                          buildFold(
                                     title   => $subline,
                                     content => $sgdef,
                                     fold    => $fold++,
                                     indent  => $indent
                          );
                        push( @vipout, $sgdef );
                    } else {

                        # No fold required; put the content in parentheses
                        push( @vipout,
                              indent( $subline . ' (' . $sgdef . ')' ),
                              $indent );
                    }
                } elsif ( $subline =~ /^template (.*)$/ ) {
                    ## TEMPLATE DEFINITION
                    my $template = $1;
                    $indent = 9;
                    my $templatedef = $h{template}{$template} || "";

                    if ( $templatedef =~ /BEGIN_FOLD/ ) {

                        # This needs a fold
                        $templatedef =
                          buildFold(
                                     title   => $subline,
                                     content => $templatedef,
                                     fold    => $fold++,
                                     indent  => $indent
                          );
                        push( @vipout, $templatedef );
                    } else {

                        # No fold required; put the content in parentheses
                        push(
                              @vipout,
                              indent(
                                      $subline . ' (' . $templatedef . ')',
                                      $indent
                              )
                        );
                    }
                } elsif ( $subline =~ /^source-nat pool ([\w\d\-\_\.]+)/ ) {
                    ## SOURCE-NAT POOL
                    my $pool = $1;
                    $indent = 9;
                    my $pooldef = $h{snatpool}{$pool};

                    if ( $pooldef =~ /BEGIN_FOLD/ ) {

                        # This needs a fold
                        $pooldef =
                          buildFold(
                                     title   => $subline,
                                     content => $pooldef,
                                     fold    => $fold++,
                                     indent  => $indent
                          );
                        push( @vipout, $pooldef );
                    } else {

                        # No fold required; put the snat IP in parentheses
                        push(
                              @vipout,
                              indent(
                                      $subline . ' (' . $pooldef . ')', $indent
                              )
                        );
                    }
                } else {
                    ## NOTHING WE CARE ABOUT FOR NOW
                    # Dump the line out as it is (it's nothing special)
                    push( @vipout, indent( $subline, $indent ) );
                }
            }
            $allvips{$activePartition}{$vipname} = \@vipout;
        } elsif ( $line =~ /^active-partition ([\w\d\-\_]+)$/ ) {
            $activePartition = $1;
        }
    }

    # Build quick 'jump to' drop down for the partitions
    my @combo;
    push( @combo, <<END);
<div class="header">
    <div class="toggle">
        <img src="plus.png" height="15px" width="15px" class="foldall" />
        <span id="foldall" class="regular">Expand All</span>
    </div>
    <div class="headercenter">A10 View-O-Matic ($device)</div>
    <div class="headerselector">View Partition: <select autofocus class="partition">
END
    foreach my $partition ( sort keys %allvips ) {
        if ( $opt{partition} ) {
            next if ( $partition ne $opt{partition} );
        }
        push( @combo, "<option value=\"$partition\">$partition</option>" );
    }
    push( @combo, "</select></div>" );

    # Print output
    print @combo;
    print @htmlDeviceCombo;
    print "</div>\n";
    print "<div class=\"mainbody\">";
    foreach my $partition ( sort keys %allvips ) {
        if ( $opt{partition} ) {
            next if ( $partition ne $opt{partition} );
        }
        print <<END;
<div class="partitionhead">Partition: <a name="$partition">$partition</a></div>
END
        foreach my $vipname ( sort keys %{ $allvips{$partition} } ) {
            print @{ $allvips{$partition}{$vipname} };
        }
    }
    print "<div class=\"generated\"><span class=\"generatedlabel\">Generated "
      . scalar gmtime()
      . "</span></div>";
    print "\n</div>\n";
    print "\n</body></html>\n\n";

}

sub addLine {
    ##
    ## Appends $add to $line, prepending a {{BEGIN_FOLD}} if
    ## this is the first addition to $line. Otherwise the line
    ## is appended and a \n is added.
    ##
    my $line = $_[0];
    my $add  = $_[1];
    $add =~ s/^\s+//;

    my $encoded = encode_entities($add);
    if ( $line eq '' ) {
        return '{{BEGIN_FOLD}}' . $add;
    } else {
        return $line . "\n" . $add;
    }
}    # end sub addLine

sub getSubLines {
    ##
    ## Continue reading configuration until the next ! line,
    ## which indicates the end of the current configuration stanza.
    ## This is used to grab the rest of a stanza once the first
    ## line has been identified in the main config loop.
    ##
    ## A couple of special cases are defined to handle embeds of
    ## other config information (e.g. server IP included inline).
    ##
    ## Finally, if the received config string begins with a FOLD
    ## marker, this will append an END_FOLD marker before return.
    ##
    my $confref    = $_[0];
    my $href       = $_[1];
    my $nextline   = $_[2];
    my $default    = $_[3];
    my $returnline = '';

    if ( $$confref[0] !~ /^$nextline/ ) {
        while ( my $subline = shift @$confref ) {
            chomp($subline);
            last if ( $subline =~ /^!/ );

            # Now we can do a little smart stuff and hope it doesn't make
            # too many assumptions...
            if ( $subline =~ /member ([\w\d\-\_\.]+):(\d+)/ ) {
                ## MEMBER WITHIN SERVICE-GROUP
                # It's a line within a service-group so expand server definition
                my $name = $1;
                my $port = $2;
                my $ip   = $$href{server}{$name} || "";
                $subline = "member $name ($ip), port $port";
            } elsif ( $subline =~ /template (.*)$/ ) {
                ## TEMPLATE DEFINITION
                # Expand the template definition
                my $name = $1;

                # The embedded cipher template also has the
                # BEGIN/END_FOLD tags, which need cleaning up.
                # Also the lines need indenting, as they are embedded
                # within another clause
                my $embed = $$href{template}{$name};
                $embed =~ s/{{BEGIN_FOLD}}/\n/;
                $embed =~ s/{{END_FOLD}}//;
                $embed =~ s/\n/\n   /g;

                $subline = $name . " " . $embed;
            }
            $returnline = addLine( $returnline, $subline );
        }
        if ( $returnline =~ /BEGIN_FOLD/ ) {
            $returnline .= '{{END_FOLD}}';
        }
    }
    if ( $returnline eq '' ) {
        $returnline = $default;
    }
    return $returnline;
}    # end sub getSubLines

sub indent {
    ##
    ## Return string as a preformatted HTML <span> indented by the
    ## requested number of spaces.
    ##
    my $string    = $_[0];
    my $indent    = $_[1];
    my $spanclass = $_[2] || "preformatted";

    my $space = " " x $indent;
    return
        '<span class="'
      . $spanclass . '">'
      . $space
      . $string
      . "</span><br />";
}    # end sub indent

sub buildFold {
    ##
    ## Return multiline string as indented HTML FOLD (e.g. <span>s + <div>)
    ## ready for insertion into the page.
    ##
    my %ARGS   = @_;
    my $string = $ARGS{content} || "";
    my $idx    = $ARGS{fold};
    my $indent = $ARGS{indent};
    my $title  = $ARGS{title};
    my $space  = " " x $indent;

    # Insert the opening heads for the fold (the expansion
    # widget plus the opening to the folding DIV)
    my $openfold = <<END;
<span class="preformatted">$space<img src="plus.png" width="10px" height="10px" id="fold$idx" class="fold" />$title</span><br /> <div id="fold" class="fold$idx">
END
    my $bigspace = " " x ( $indent + 3 );
    $openfold .= '<span class="preformatted">' . $bigspace;
    $string =~ s/\n/\n$bigspace/g;
    $string =~ s/{{BEGIN_FOLD}}/$openfold/;

    my $closefold = <<END;
</span>
</div>

END
    $string =~ s/{{END_FOLD}}/$closefold/;
    return $string;
}    # end sub buildFold

sub fail {
    ##
    ## Print failure message(s) to STDERR then return exit code of 1.
    ## Intended to be called as exit(fail("<some reason>"));
    ##
    map { print STDERR $_ . "\n"; } @_;
    return 1;
}    # end sub fail
