# a10-2-html #

## What Does It Do? ##

If you use an A10 Networks ADC (Application Delivery Controller), you'll recognize that both in the web UI and in the CLI, the configuration for a given VIP makes references to other configuration elements, and they in turn have references to still more configuration elements. In the web UI this means memorizing object names and then browsing to find them, and at the CLI, even if you have a local copy of the configuration so that you can more easily move around in it, all the cross references are still a huge pain to follow. This script takes as input A10 configuration files (generated using "show running all-partitions") and creates a page of HTML to STDOUT. The HTML is VIP-centric, and for a given VIP allows you to easily see the reference configuration by embedding it as a 'fold' at the appropriate place within the output.

If that sounds complicated, the easiest thing to do is to read my blog post "(Unwrapping Tangled Device Configurations – A10 Networks Edition)[http://movingpackets.net/2016/09/27/unwrapping-device-configurations-a10/]", which has screenshots demonstrating the script in action. 

Note that if configuration is not directly related to a VIP, it will not show in the output.

Is it perfect? Of course not; don't be silly.

## Why? ##

Because it makes viewing the VIP configurations much easier. I use this to show selected VIP and partition configurations to my internal customers, and have found that they are able to interpret the configuration much more easily than if I gave them the full configuration. That in turn has reduced the number of support calls asking how a particular VIP of theirs is currently configured, whether a server had been manually disabled, and so on.

## Behavior / Command Line Options ##

When run, a10-2-html.pl will scan the configuration directory and process all the A10 configuration files within. The following options restrict the output based on a few parameters:

    -d=<name>     Only process device called <name>
    -p=<name>     Only process partition called <name>
    -m=<string>   Only process VIPs whose name contains <string>

## Related Files ##

The files 'plus.png' and 'minus.png' must be copied to the same directory as the output html file. I hacked these together quickly in Pixelmator if I recall correctly; feel free to use nicer ones if you would like ;-)

The file 'header.htm' contains the CSS for the page, and can be tweaked to your heart's content. Have at it, why doncha?

## Variables to Tweak ##

I didn't put variables in an external file yet, so you may need to go in and tweak $configDir, $a10pattern and $htmlHeader to suit your site needs. $configDir is a directory where all the A10 configurations are stored. $a10pattern is the file suffice which identifies A10 configuration files. The script assumes that everything before the first '.' in a filename is the hostname of the device.

## Usage Examples ##

I tend to call this script from a batch file. I will have a list of device names in a file called 'devicelist', and the call will be something like this:

    # Generate full outputs
    for device in `cat devicelist`; do
        perl a10-2-html.pl -d $device > link_to_a10/$device.htm
    done

I then generate additional separate outputs for partition owners and, because of the naming policy I use for VIPs, I can also generate output containing all the VIPs owned by a particular person or team.

See? It's almost too easy.

# Updates #

I'm sure there are templates that I have not yet parsed and embedded, and over time I will add more I'm sure. Failing tht, though, please feel free to clone the repo and enhance it with your own, and I'd appreciate a pull request if you are successful!
