# FQDN Lookup
The objective of this script is to parse DNS zone files, GTM configs, and LTM configs to correlate LTM VIP addresses with FQDNs (A and CNAME) from the zone files as well as wideips and aliases from GTM configs.

## Requirements

### Running the script
The file must be run on a linux host which can be a BIG-IP device.

### Directory structure 
The directory structure must contain the following directories relative to the location of the script.
  1. configs: Contains directories for the GTM configs, LTM configs, and DNS zonefiles.
      - gtm: Directory for one or more bigip_gtm.conf files
      - ltm: Directory for one or more LTM bigip.conf files
      - zonefiles: Directory for one or more DNS zone files
  2. outputs: Directory where the output CSV files will be written
  
  ```
    .
    ├── configs
    │   ├── gtm
    │   │   ├── ext_bigip_gtm.conf
    │   │   └── int_bigip_gtm.conf
    │   ├── ltm
    │   │   ├── int01_bigip.conf
    │   │   ├── ext01_bigip.conf
    │   └── zonefiles
    │       ├── ap.example.txt
    │       ├── eu.example.txt
    │       ├── example.txt
    │       └── na.example.txt
    ├── outputs
    └── fqdnLookup.pl
```
The directories must be created and required GTM configs, LTM configs, and DNS zone files must be in place before the script is run.

**Note:** if the directory names are different than those shown above, the path variables in the script (lines 9-12) must be modified to reflect the new relative paths.
```
    my $zonefilePath = "configs/zonefiles/";
    my $gtmfilePath = "configs/gtm/";
    my $ltmfilePath = "configs/ltm/";
    my $outputPath = "outputs/";
```
## Usage
From the directory containing the script, execute the script.
```
./fqdnLookup.pl
```
Standard output will look like the following when the script executes and completes successfully
```
# Reading zone info for ap.example.com
# Reading zone info for eu.example.com
# Reading zone info for example.com
# Reading zone info for na.example.com
# Reading GTM info from configs/gtm/ext_bigip_gtm.conf
# Reading GTM info from configs/gtm/int_bigip_gtm.conf
# Assembling GTM info for ext_bigip_gtm.conf
# Assembling GTM info for int_bigip_gtm.conf
# Reading LTM info from configs/ltm/int01_bigip.conf
# Reading LTM info from configs/ltm/ext01_bigip.conf
# Getting fqdn info for VIPs in int01_bigip.conf
# Getting fqdn info for VIPs in ext01_bigip.conf
# Output of int01_bigip.conf is at outputs/int01_bigip.csv
# Output of ext01_bigip.conf is at outputs/ext01_bigip.csv
```

## Output files
One output file will be written for each LTM config in the **configs/LTM/** directory. The output files will be formated as CSV files and will be written to the **outputs/** directory with the following columns ordered from right to left.

**VS Names (column A):** contains all Virtual Server names that are associated with a given Internal VIP address.

**IP Address(int) (column B):** contains internal VIP address taken from the LTM config.

**IP Address(ext) (column C):** contains external address associated with the internal VIP address. This info is taken from the GTM config.

**VS Ports (column D):** contains all VIP ports associated with a given VIP address.

**FQDNs from Zone Files (column E):** contains all FQDN (A or CNAME) records associated with a given VIP address from all DNS zone files in **configs/zonefiles/**.

**WideIPs from GTM config (column F):** contains all wideip names and aliases associated with a given VIP address from all GTM config files in **configs/gtm/**.

**VS Descriptions (column G):** contains all description text taken from all virtual servers associated with the given internal VIP address (column B). Information is taken from LTM config files in **configs/ltm/**.

