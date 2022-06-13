
<#	SCRIPT DETAILS
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Group:         HCI BU
    .Organization:  VMware, Inc.
    .Version:       1.0 (Build 002)
    .Date:          2020-02-07
    ===============================================================================================================
    .CREDITS

    - Willian Lam - Set-VMKeystrokes Function
    - William Lam & Ken Gould - LogMessage Function

    ===============================================================================================================
    .CHANGE_LOG

    - 1.0.001 (Gary Blake / 2020-02-03) - Initial script creation
    - 1.0.002 (Gary Blake / 2020-02-07) - Added support for Thin provisioning of additonal hard disks
                                        - Added check for existing virtual machine and perform clean up
                                        - Added Optional -type switch to configure different storage size for WLD

    ===============================================================================================================
    .DESCRIPTION
        This script automates the following procedures to help with preparing nested ESXi hosts for use
        with VMware Cloud Foundation:
        - Creation of the nested ESXi Host
        - Automated interactive installation of ESXi
        - Enabling SSH Service
        - Configure NTP

    .EXAMPLE
    .\createNestedEsxuHost.ps1 -hostname sfo01m01esx01 -IpAddress 192.168.110.51 -type WLD
#>

    param(
    [Parameter(Mandatory=$true)]
    [String]$hostname,
    [Parameter(Mandatory=$true)]
    [String]$IpAddress,
    [Parameter(Mandatory=$false)]
    [String]$type
    )


# Set your Variables here

$Global:vcenterServer = "lab01vc01.sddc.local"
$Global:esxiHost = "lab01esx01.sddc.local"
$Global:credsUsername = "administrator@vsphere.local"
$Global:credsPassword = "VMw@re1!"
$Global:datastore = "lab01vmfs01"
$Global:esxiHostname = $hostname
$Global:esxiIsoPath = "[lab01esx01-local] ISOs\VMware-VMvisor-Installer-6.7.0-15160138.x86_64.iso"

$Global:nestedCpu = "8"
$Global:nestedMemory = "64" # GB
$Global:nestedDiskDriveBoot = "16" # GB
$Global:nestedDiskDriveCache = "32" # GB
$Global:nestedDiskDriveMgmt = "140" # GB
$Global:nestedDiskDriveWld = "80" # GB

$Global:UseVlan = "No" #Use Yes/No here, if you would like to assign a vlan to your esxi host
$Global:VlanID = "" #If using the above option, set VLAN ID here. If not leave blank ""
$Global:DNSSuffix = "sddc.local" #Set ESXi DNS suffix
$Global:RootPw = "VMw@re1!" #Set ESXi Root Password
$Global:VirtualMachine = $esxiHostname #Set your nested ESXi VM Name here
$Global:Ipv4Address = $IpAddress #Set ESXi Host IP Address
$Global:Ipv4Subnet = "255.255.255.0" #Set ESXi Host Subnet Mask
$Global:Ipv4Gateway = "192.168.110.1" #Set ESXi Host Default Gateway
$Global:PrimaryDNS = "192.168.178.103" #Set ESXi Host Primary DNS
$Global:AlternateDNS = "192.168.178.104" #Set ESXi Host Alternate DNS
$Global:HostName = $esxiHostname+"."+$DNSSuffix #Set ESXi Host Name
$Global:primaryNtp = "ntp0.sddc.local"
$Global:secondaryNtp = "ntp1.sddc.local"

Function LogMessage {
    param(
    [Parameter(Mandatory=$true)]
    [String]$message,
    [Parameter(Mandatory=$false)]
    [String]$colour,
    [Parameter(Mandatory=$false)]
    [string]$skipnewline
    )

    If (!$colour) {
        $colour = "green"
    }

    $timeStamp = Get-Date -Format "MM-dd-yyyy_hh:mm:ss"

    Write-Host -NoNewline -ForegroundColor White " [$timestamp]"
    If ($skipnewline) {
        Write-Host -NoNewline -ForegroundColor $colour " $message"
    }
    else {
        Write-Host -ForegroundColor $colour " $message"
    }

}

Function Set-VMKeystrokes {
<#
    .NOTES
    ===========================================================================
     Created by:    William Lam
     Organization:  VMware
     Blog:          www.virtuallyghetto.com
     Twitter:       @lamw
    ===========================================================================
    .DESCRIPTION
        This function sends a series of character keystrokse to a particular VM
    .PARAMETER VMName
		The name of a VM to send keystrokes to
	.PARAMETER StringInput
		The string of characters to send to VM
	.PARAMETER DebugOn
		Enable debugging which will output input charcaters and their mappings
    .EXAMPLE
        Set-VMKeystrokes -VMName $VM -StringInput "root"
    .EXAMPLE
        Set-VMKeystrokes -VMName $VM -StringInput "root" -ReturnCarriage $true
    .EXAMPLE
        Set-VMKeystrokes -VMName $VM -StringInput "root" -DebugOn $true
    ===========================================================================
     Modified by:   David Rodriguez
     Organization:  Sysadmintutorials
     Blog:          www.sysadmintutorials.com
     Twitter:       @systutorials
    ===========================================================================
    .MODS
        Made $StringInput Optional
        Added a $SpecialKeyInput - See PARAMETER SpecialKeyInput below
        Added description to write-hosts [SCRIPTINPUT] OR [SPECIALKEYINPUT]
    .PARAMETER StringInput
        The string of single characters to send to the VM
    .PARAMETER SpecialKeyInput
        All Function Keys i.e. F1 - F12
        Keyboard TAB, ESC, BACKSPACE, ENTER
        Keyboard Up, Down, Left Right
    .EXAMPLE
        Set-VMKeystrokes -VMName $VM -SpecialKeyInput "F2"

#>
    param(
        [Parameter(Mandatory=$true)][String]$VMName,
        [Parameter(Mandatory=$false)][String]$StringInput,
        [Parameter(Mandatory=$false)][String]$SpecialKeyInput,
        [Parameter(Mandatory=$false)][Boolean]$ReturnCarriage,
        [Parameter(Mandatory=$false)][Boolean]$DebugOn
    )

    # Map subset of USB HID keyboard scancodes
    # https://gist.github.com/MightyPork/6da26e382a7ad91b5496ee55fdc73db2
    $hidCharacterMap = @{
		"a"="0x04";
		"b"="0x05";
		"c"="0x06";
		"d"="0x07";
		"e"="0x08";
		"f"="0x09";
		"g"="0x0a";
		"h"="0x0b";
		"i"="0x0c";
		"j"="0x0d";
		"k"="0x0e";
		"l"="0x0f";
		"m"="0x10";
		"n"="0x11";
		"o"="0x12";
		"p"="0x13";
		"q"="0x14";
		"r"="0x15";
		"s"="0x16";
		"t"="0x17";
		"u"="0x18";
		"v"="0x19";
		"w"="0x1a";
		"x"="0x1b";
		"y"="0x1c";
		"z"="0x1d";
		"1"="0x1e";
		"2"="0x1f";
		"3"="0x20";
		"4"="0x21";
		"5"="0x22";
		"6"="0x23";
		"7"="0x24";
		"8"="0x25";
		"9"="0x26";
		"0"="0x27";
		"!"="0x1e";
		"@"="0x1f";
		"#"="0x20";
		"$"="0x21";
		"%"="0x22";
		"^"="0x23";
		"&"="0x24";
		"*"="0x25";
		"("="0x26";
		")"="0x27";
		"_"="0x2d";
		"+"="0x2e";
		"{"="0x2f";
		"}"="0x30";
		"|"="0x31";
		":"="0x33";
		"`""="0x34";
		"~"="0x35";
		"<"="0x36";
		">"="0x37";
		"?"="0x38";
		"-"="0x2d";
		"="="0x2e";
		"["="0x2f";
		"]"="0x30";
		"\"="0x31";
		"`;"="0x33";
		"`'"="0x34";
		","="0x36";
		"."="0x37";
		"/"="0x38";
		" "="0x2c";
        "F1"="0x3a";
        "F2"="0x3b";
        "F3"="0x3c";
        "F4"="0x3d";
        "F5"="0x3e";
        "F6"="0x3f";
        "F7"="0x40";
        "F8"="0x41";
        "F9"="0x42";
        "F10"="0x43";
        "F11"="0x44";
        "F12"="0x45";
        "TAB"="0x2b";
        "KeyUp"="0x52";
        "KeyDown"="0x51";
        "KeyLeft"="0x50";
        "KeyRight"="0x4f";
        "KeyESC"="0x29";
        "KeyBackSpace"="0x2a";
        "KeyEnter"="0x28";
        "KeySpace"="0x2c";
    }

    $vm = Get-View -ViewType VirtualMachine -Filter @{"Name"="^$($VMName)$"}

	# Verify we have a VM or fail
    if(!$vm) {
        Write-host "Unable to find VM $VMName"
        return
    }

    #Code for -StringInput
    if($StringInput)
    {
        $hidCodesEvents = @()
    foreach($character in $StringInput.ToCharArray()) {
        # Check to see if we've mapped the character to HID code
        if($hidCharacterMap.ContainsKey([string]$character)) {
            $hidCode = $hidCharacterMap[[string]$character]

            $tmp = New-Object VMware.Vim.UsbScanCodeSpecKeyEvent

            # Add leftShift modifer for capital letters and/or special characters
            if( ($character -cmatch "[A-Z]") -or ($character -match "[!|@|#|$|%|^|&|(|)|_|+|{|}|||:|~|<|>|?|*]") ) {
                $modifer = New-Object Vmware.Vim.UsbScanCodeSpecModifierType
                $modifer.LeftShift = $true
                $tmp.Modifiers = $modifer
            }

            # Convert to expected HID code format
            $hidCodeHexToInt = [Convert]::ToInt64($hidCode,"16")
            $hidCodeValue = ($hidCodeHexToInt -shl 16) -bor 0007

            $tmp.UsbHidCode = $hidCodeValue
            $hidCodesEvents+=$tmp

            if($DebugOn) {
                Write-Host "[StringInput] Character: $character -> HIDCode: $hidCode -> HIDCodeValue: $hidCodeValue"
            }
        } else {
            Write-Host "[StringInput] The following character `"$character`" has not been mapped, you will need to manually process this character"
            break
        }

    }
    }

    #Code for -SpecialKeyInput
     if($SpecialKeyInput)
     {
       if($hidCharacterMap.ContainsKey([string]$SpecialKeyInput))
        {
        $hidCode = $hidCharacterMap[[string]$SpecialKeyInput]
        $tmp = New-Object VMware.Vim.UsbScanCodeSpecKeyEvent
        $hidCodeHexToInt = [Convert]::ToInt64($hidCode,"16")
            $hidCodeValue = ($hidCodeHexToInt -shl 16) -bor 0007

            $tmp.UsbHidCode = $hidCodeValue
            $hidCodesEvents+=$tmp

            if($DebugOn) {
                Write-Host "[SpecialKeyInput] Character: $character -> HIDCode: $hidCode -> HIDCodeValue: $hidCodeValue"
            }
        } else {
            Write-Host "[SpecialKeyInput] The following character `"$character`" has not been mapped, you will need to manually process this character"
            break
        }
    }

    # Add return carriage to the end of the string input (useful for logins or executing commands)
    if($ReturnCarriage) {
        # Convert return carriage to HID code format
        $hidCodeHexToInt = [Convert]::ToInt64("0x28","16")
        $hidCodeValue = ($hidCodeHexToInt -shl 16) + 7

        $tmp = New-Object VMware.Vim.UsbScanCodeSpecKeyEvent
        $tmp.UsbHidCode = $hidCodeValue
        $hidCodesEvents+=$tmp
    }

    # Call API to send keystrokes to VM
    $spec = New-Object Vmware.Vim.UsbScanCodeSpec
    $spec.KeyEvents = $hidCodesEvents
    Write-Host "Sending keystrokes to $VMName ...`n"
    $results = $vm.PutUsbScanCodes($spec)
}

Function createNestedEsxiVm {

    LogMessage "Checking for Pre-existing Nested ESXi Virtual Machine $esxiHostname"
    Try {
        $esxiHostnameExists = Get-VM -Name $esxiHostname -ErrorAction SilentlyContinue
    }
    Catch {
        $ErrorMessage = $_.Exception.Message
        LogMessage "Failed to Connect to $esxiHost" Red
        LogMessage "Error was: $ErrorMessage" Red
    }
    If ($esxiHostnameExists) {
        LogMessage "A nested ESXi virtual machine called $esxiHostname already exists on host" Yellow
        LogMessage "Would you like to delete this existing virtual machine $esxiHostname (Y/N) " yellow
        $confirmation = Read-Host
        if ($confirmation -eq 'Y') {
            Try {
                LogMessage "Checking the power status of nested ESXi virtual machine $esxiHostname"
                $powerState = Get-VM -Name $esxiHostname
                if ($powerState.PowerState -eq 'PoweredOn') {
                    LogMessage "Powering off nested ESXi virtual machine $esxiHostname"
                    Stop-VM -VM $esxiHostname -Confirm:$false | Out-Null
                }
                LogMessage "Deleting nested ESXi virtual machine $esxiHostname"
                Remove-VM -VM $esxiHostname -DeletePermanently -Confirm:$false
            }
            Catch {
                $ErrorMessage = $_.Exception.Message
                LogMessage "Issue occured trying to power off and delete $esxiHostname" Red
                LogMessage "Error was: $ErrorMessage" Red
            }
        }
        else {
            Exit
        }
    }
    Try {
        LogMessage "Creating Nested ESXi Virtual Machine $esxiHostname"
        New-VM -VMhost $esxiHost -Name $esxiHostname -Datastore $datastore -DiskGB $nestedDiskDriveBoot -DiskStorageFormat Thin -MemoryGB $nestedMemory -NumCpu $nestedCpu -GuestID vmkernel65Guest -Confirm:$false | Out-Null

        LogMessage "Adding Additional Hard Disks to Nested ESXi Virtual Machine $esxiHostname"
        Get-VM $esxiHostname | New-HardDisk -CapacityGB $nestedDiskDriveCache -StorageFormat Thin -Confirm:$false | Out-Null
        if ($type -eq 'WLD') {
            Get-VM $esxiHostname | New-HardDisk -CapacityGB $nestedDiskDriveWld -StorageFormat Thin -Confirm:$false | Out-Null
        }
        else {
            Get-VM $esxiHostname | New-HardDisk -CapacityGB $nestedDiskDriveMgmt -StorageFormat Thin -Confirm:$false | Out-Null
        }
        if ($type -eq 'WLD') {
            Get-VM $esxiHostname | New-HardDisk -CapacityGB $nestedDiskDriveWld -StorageFormat Thin -Confirm:$false | Out-Null
        }
        else {
            Get-VM $esxiHostname | New-HardDisk -CapacityGB $nestedDiskDriveMgmt -StorageFormat Thin -Confirm:$false | Out-Null
        }

        LogMessage "Configuring Network Adapters on Nested ESXi Virtual Machine $esxiHostname"
        Get-NetworkAdapter -VM $esxiHostname | Remove-NetworkAdapter -Confirm:$false | Out-Null
        New-NetworkAdapter -VM $esxiHostname -NetworkName "VM Network" -StartConnected -Type Vmxnet3 -Confirm:$false | Out-Null
        New-NetworkAdapter -VM $esxiHostname -NetworkName "VM Network" -StartConnected -Type Vmxnet3 -Confirm:$false | Out-Null

        LogMessage "Adding a CD-Rom Drive and Attaching the ESXi ISO to Nested ESXi Virtual Machine $esxiHostname $esxiHostname"
        New-CDDrive -VM $esxiHostname | Set-CDDrive -IsoPath $esxiIsoPath -StartConnected:$true -Confirm:$false | Out-Null

        LogMessage "Configuring Hard Disks to look like SSD Drives on Nested ESXi Virtual Machine $esxiHostname"
        Get-VM $esxiHostname | New-AdvancedSetting -Name "scsi0:1.virtualSSD" -Value "1" -Confirm:$false | Out-Null
        Get-VM $esxiHostname | New-AdvancedSetting -Name "scsi0:2.virtualSSD" -Value "1" -Confirm:$false | Out-Null
        Get-VM $esxiHostname | New-AdvancedSetting -Name "scsi0:3.virtualSSD" -Value "1" -Confirm:$false | Out-Null

        LogMessage "Configuring Hardware Virtualization on Nested ESXi Virtual Machine $esxiHostname"
        $vm = Get-VM $esxiHostname
        $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
        $spec.nestedHVEnabled = $true
        $vm.ExtensionData.ReconfigVM($spec)

        LogMessage "Powering on Nested ESXi Virtual Machine $esxiHostname"
        Start-VM $esxiHostname | Out-Null

        LogMessage "Waiting for Nested ESXi Virtual Machine $esxiHostname to Power On and Boot into the ESXi Installer (80 seconds)"
        SLEEP 80
    }
    Catch {
        $ErrorMessage = $_.Exception.Message
        LogMessage "Error creating nested ESXi VM $esxiHostname" Red
        LogMessage "Error was: $ErrorMessage" Red
    }
}

Function installEsxi {
    # From this point forward, the ESXi configuration starts

    Try {
        LogMessage "Starting Automatic Installation of ESXi on Nested ESXi Virtual Machine $esxiHostname"
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyEnter" -DebugOn $True | Out-Null #ESXi Setup - Key Enter
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "F11" -DebugOn $True | Out-Null #ESXi Setup - Press F11 to accept EULA
        SLEEP 10

        LogMessage "Setting the Default Keyboard"
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyEnter" -DebugOn $True | Out-Null #ESXi Setup - Key Enter
        SLEEP 5

        LogMessage "Setting Root Password for Nested ESXi"
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyEnter" -DebugOn $True | Out-Null #ESXi Setup - Key Enter
        SLEEP 5

        Set-VMKeystrokes -VMName $VirtualMachine -StringInput "$RootPw" -ReturnCarriage $True -DebugOn $True | Out-Null #ESXi Setup - Root password
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "TAB" -DebugOn $True | Out-Null #ESXi Setup - Root password
        Set-VMKeystrokes -VMName $VirtualMachine -StringInput "$RootPw" -ReturnCarriage $True -DebugOn $True | Out-Null #ESXi Setup - Root password
        SLEEP 5

        LogMessage "Installation of ESXi In Progress"
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "F11" -DebugOn $True | Out-Null #ESXi Setup - Begin Installation
        LogMessage "Waiting for ESXi Installation to Complete (60 seconds)"
        SLEEP 60

        LogMessage "Installation of ESXi Complete Waiting for the Host to Reboot (90 seconds)"
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyEnter" -DebugOn $True | Out-Null #ESXi Setup - Key Enter
        SLEEP 90

        #Start ESXi Configuration

        LogMessage "Configuring Nested ESXi Host IP Address and DNS Configuration"
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "F2" -DebugOn $True | Out-Null #ESXi Setup - F2 to login
        SLEEP 5

        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "TAB" -DebugOn $True | Out-Null #ESXi Setup - Tab to Password
        Set-VMKeystrokes -VMName $VirtualMachine -StringInput "$RootPw" -ReturnCarriage $True -DebugOn $True | Out-Null #ESXi Setup - Root password
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyEnter" -DebugOn $True | Out-Null #ESXi Setup - Key Enter
        SLEEP 5

        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyDown" -DebugOn $True | Out-Null #ESXi Setup - Key Down to Configure Management Network
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyEnter" -DebugOn $True | Out-Null #ESXi Setup - Key Enter
        SLEEP 5

        #Set IPv4 Configuration

        LogMessage "Configuring Static IPv4 Settings on the ESXi Host"
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyDown" -DebugOn $True | Out-Null #ESXi Setup - Key Down
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyDown" -DebugOn $True | Out-Null #ESXi Setup - Key Down
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyEnter" -DebugOn $True | Out-Null #ESXi Setup - Key Enter
        SLEEP 5

        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyDown" -DebugOn $True | Out-Null #ESXi Setup - Key Down
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyDown" -DebugOn $True | Out-Null #ESXi Setup - Key Down
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeySpace" -DebugOn $True | Out-Null #ESXi Setup - Key Space Bar
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyDown" -DebugOn $True | Out-Null #ESXi Setup - Key Down
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyBackSpace" -DebugOn $True | Out-Null #ESXi Setup - Remove existing IPv4 Address
        Set-VMKeystrokes -VMName $VirtualMachine -StringInput "$Ipv4Address" -DebugOn $True | Out-Null #ESXi Setup - Enter IPv4 Address
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyDown" -DebugOn $True | Out-Null #ESXi Setup - Key Down
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyBackSpace" -DebugOn $True | Out-Null #ESXi Setup - Remove existing IPv4 Subnet
        Set-VMKeystrokes -VMName $VirtualMachine -StringInput "$Ipv4Subnet" -DebugOn $True | Out-Null #ESXi Setup - Enter IPv4 Subnet
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyDown" -DebugOn $True | Out-Null #ESXi Setup - Key Down
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyBackSpace" -DebugOn $True | Out-Null #ESXi Setup - Remove existing IPv4 Default Gateway
        Set-VMKeystrokes -VMName $VirtualMachine -StringInput "$Ipv4Gateway" -DebugOn $True | Out-Null #ESXi Setup - Enter IPv4 Subnet
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyEnter" -DebugOn $True | Out-Null #ESXi Setup - Remove existing IPv4 Default Gateway
        SLEEP 5

        #Disable IPv6

        LogMessage "Disabling IPv6 on the ESXi Host"
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyDown" -DebugOn $True | Out-Null #ESXi Setup - Key Down
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyEnter" -DebugOn $True | Out-Null #ESXi Setup - IPv6 Configuration
        SLEEP 5

        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyUp" -DebugOn $True | Out-Null #ESXi Setup - Key Down
        Set-VMKeystrokes -VMName $VirtualMachine -StringInput " " -DebugOn $True | Out-Null #ESXi Setup - Select Disable IPv6
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyEnter" -DebugOn $True | Out-Null #ESXi Setup - IPv6 Commit Changes
        SLEEP 5

        #Set DNS Configuration

        LogMessage "Configuring DNS Servers on ESXi Host"
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyDown" -DebugOn $True | Out-Null #ESXi Setup - Key Down
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyEnter" -DebugOn $True | Out-Null #ESXi Setup - DNS Configuration
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyDown" -DebugOn $True | Out-Null #ESXi Setup - Key Down
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeySpace" -DebugOn $True | Out-Null #ESXi Setup - Key Space Bar
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyDown" -DebugOn $True | Out-Null #ESXi Setup - Key Down
        SLEEP 5

        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyBackSpace" -DebugOn $True | Out-Null #ESXi Setup - Remove existing Primary DNS
        Set-VMKeystrokes -VMName $VirtualMachine -StringInput "$PrimaryDNS" -DebugOn $True | Out-Null #ESXi Setup - Primary DNS IP Address
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyDown" -DebugOn $True | Out-Null #ESXi Setup - Key Down
        Set-VMKeystrokes -VMName $VirtualMachine -StringInput "$AlternateDNS" -DebugOn $True | Out-Null #ESXi Setup - Alternate DNS IP Address
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyDown" -DebugOn $True | Out-Null #ESXi Setup - Key Down
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyBackSpace" -DebugOn $True | Out-Null #ESXi Setup - Remove existing Hostname
        Set-VMKeystrokes -VMName $VirtualMachine -StringInput "$HostName" -DebugOn $True | Out-Null #ESXi Setup -Hostname
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyEnter" -DebugOn $True | Out-Null #ESXi Setup - DNS Commit Changes
        SLEEP 5

        #Set Custom DNS Suffixes

        LogMessage "Configuring Custom DNS Suffixes on the ESXi Host"
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyDown" -DebugOn $True | Out-Null #ESXi Setup - Key Down
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyEnter" -DebugOn $True | Out-Null #ESXi Setup - Enter
        SLEEP 5

        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyBackSpace" -DebugOn $True | Out-Null #ESXi Setup - Remove existing Suffixes
        Set-VMKeystrokes -VMName $VirtualMachine -StringInput "$DNSSuffix" -DebugOn $True | Out-Null #ESXi Setup - DNS Suffix
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyEnter" -DebugOn $True | Out-Null #ESXi Setup - Enter
        SLEEP 5

        #Complete Setup and Reboot

        LogMessage "Rebooting ESXi to Complete IP Address and DNS Configuration"
        Set-VMKeystrokes -VMName $VirtualMachine -SpecialKeyInput "KeyESC" -DebugOn $True | Out-Null #ESXi Setup - ESC back
        SLEEP 5

        Set-VMKeystrokes -VMName $VirtualMachine -StringInput "Y" -DebugOn $True | Out-Null #ESXi Setup - Apply Changes and reboot host
        LogMessage "ESXi Installation and Configuration Complete" Yellow
        LogMessage "Waiting for ESXi 90 seconds"
        SLEEP 90
    }
    Catch {
        $ErrorMessage = $_.Exception.Message
        LogMessage "Error installing ESXi for $esxiHostname" Red
        LogMessage "Error was: $ErrorMessage" Red
    }
}

Function enableSsh {

    Try {
        LogMessage "Enabling SSH and setting and auto-start policy on $esxiHostname"
        Get-VMHostService | Where {$_.key -eq 'TSM-SSH'} | Start-VMHostService -Confirm:$false | Out-Null
        Set-VMHostService -HostService (Get-VMHostservice | Where {$_.key -eq 'TSM-SSH'}) -Policy "On" | Out-Null
        Get-VMHostNetwork -VMHost $esxiHostname | Set-VMHostNetwork -DomainName $DNSSuffix -SearchDomain $DNSSuffix -Confirm:$false | Out-Null
    }
    Catch {
        $ErrorMessage = $_.Exception.Message
        LogMessage "Error configuring SSH for $esxiHostname" Red
        LogMessage "Error was: $ErrorMessage" Red
    }
}

Function configureHostNtp {

    Try {
        LogMessage "Configuring NTP and setting an auto-start policy on $esxiHostname"
        $CurrentNTPServerList = Get-VMHostNtpServer -VMHost $esxiHostname
        if ($CurrentNTPServerList -ne "") {
            ForEach ($NtpServer in $CurrentNTPServerList){
                Remove-VMHostNtpServer -VMHost $esxiHostname -NtpServer $NtpServer -Confirm:$false | Out-Null
                LogMessage "Removing NTP Server $NtpServer on $esxiHostname"
            }
        }
        LogMessage "Adding $primaryNtp to $esxiHostname"
        Add-VMHostNtpServer -VMHost $esxiHostname -NtpServer $primaryNtp -Confirm:$false | Out-Null
        LogMessage "Adding $secondaryNtp to $esxiHostname"
        Add-VMHostNtpServer -VMHost $esxiHostname -NtpServer $secondaryNtp -Confirm:$false | Out-Null
        LogMessage "Reconfiguring NTP Startup Policy"
        Set-VMHostService -HostService (Get-VMHostservice | Where {$_.key -eq "ntpd"}) -Policy "On" | Out-Null
        LogMessage "Restarting NTP Service"
        Get-VMHostService | Where {$_.key -eq 'ntpd'} | Stop-VMHostService -Confirm:$false | Out-Null
        Get-VMHostService | Where {$_.key -eq 'ntpd'} | Start-VMHostService -Confirm:$false | Out-Null
        LogMessage "Successfully configured NTP settings on $esxiHostname"
    }
    Catch {
        $ErrorMessage = $_.Exception.Message
        LogMessage "Error configuring NTP for $esxiHostname" Red
        LogMessage "Error was: $ErrorMessage" Red
    }
}

Function disableCeip {

    Try {
        LogMessage "Disabling the Customer Experience Improvement Program (CEIP) on $esxiHostname"
        Get-AdvancedSetting -Entity $esxiHostname -Name UserVars.HostClientCEIPOptIn | Set-AdvancedSetting -Value 2 -Confirm:$false | Out-Null

    }
    Catch {
        $ErrorMessage = $_.Exception.Message
        LogMessage "Error disabling Customer Experience Improvement Program (CEIP) on $esxiHostname" Red
        LogMessage "Error was: $ErrorMessage" Red
    }
}

Clear-Host
LogMessage "Connecting to Lab Virtual Center $vcenterServer"
Connect-VIServer -Server $vcenterServer -User $credsUsername -Password $credsPassword | Out-Null # Connect to vCenter Server
createNestedEsxiVm
installEsxi
Disconnect-VIServer * -Confirm:$false | Out-Null

LogMessage "Connecting to Nested ESXi Virtual Machine $esxiHostname"
Connect-VIServer -Server $esxiHostname -User root -Password $credsPassword | Out-Null # Connect to ESXi Host
enableSsh
configureHostNtp
disableCeip
Disconnect-VIServer * -Confirm:$false | Out-Null
