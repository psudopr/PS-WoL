# psudoPR and Gemini 2.5 Pro
# Origionally modified from Chris Warwick, @cjwarwickps, November 2015

function Invoke-WakeOnLan {
    <#
    .Synopsis
        This cmdlet sends Wake-on-Lan Magic Packets to the specified Mac addresses.
    .Description
        Wake on Lan (WOL) uses a "Magic Packet" that consists of six bytes of 0xFF, followed by 16 copies of the 6-byte (48-bit)
        target MAC address (see http://en.wikipedia.org/wiki/Wake-on-LAN).

        This packet is sent via UDP to the LAN Broadcast addresses (255.255.255.255) on arbitrary Port 4000.

        Construction of this packet in PowerShell is very straight-forward: ("$Packet = [Byte[]](,0xFF*6)+($Mac*16)").

        This script uses an external JSON file (WakeOnLan.aliases.json) for a table of saved MAC addresses to allow machine aliases
        to be specified as parameters to the function. This file must be in the same directory as the module.
        The script uses a regex to validate MAC address strings.

    .Example
        Invoke-WakeOnLan 00-1F-D0-98-CD-44
        Sends WOL packets to the specified address
    .Example
        Invoke-WakeOnLan 00-1F-D0-98-CD-44, 00-1D-92-3B-C2-C8
        Sends WOL packets to the specified addresses
    .Example
        00-1F-D0-98-CD-44, 00-1D-92-3B-C2-C8 | Invoke-WakeOnLan
        Sends WOL packets to the specified addresses
    .Example
        Invoke-WakeOnLan Server3
        Sends WOL packets to the specified target using an alias. The alias must be defined in the WakeOnLan.aliases.json file.
    .Inputs
        An array of MAC addresses. Each address must be specified as a sequence of 6 hex-coded bytes seperated by ':' or '-'.
        The input can also contain aliases defined in the WakeOnLan.aliases.json file.
        MAC addresses or aliases can be piped to the cmdlet.
    .Outputs
        Wake-on-Lan packets are sent to the specified addresses
    .Parameter MacAddress
        An array of MAC addresses or aliases. Each address must be specified as a sequence of 6 hex-coded bytes seperated by ':' or '-'.
    .Functionality
        Sends Wake-on-Lan Magic Packets to the specified Mac addresses
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [string[]]$MacAddress
    )

    begin {
        $LookupTable = @{}
        # Path to the alias file, located in the same directory as the script module.
        $aliasFilePath = Join-Path -Path $PSScriptRoot -ChildPath 'WakeOnLan.aliases.json'

        if (Test-Path -Path $aliasFilePath) {
            try {
                $jsonObject = Get-Content -Path $aliasFilePath -Raw | ConvertFrom-Json
                if ($null -ne $jsonObject) {
                    foreach ($key in $jsonObject.PSObject.Properties.Name) {
                        $LookupTable.Add($key, $jsonObject.$key)
                    }
                }
            }
            catch {
                New-Item -Path $PSScriptRoot -ItemType 'File' -Name 'WakeOnLan.aliases.json'
                Write-Warning "Could not read or parse alias file at '$aliasFilePath'. Error: $_. Only explicit MAC addresses will be used."
            }
        }

        $UdpClient = New-Object System.Net.Sockets.UdpClient
        $UdpClient.EnableBroadcast = $true
        $IPEndPoint = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Broadcast, 4000)
    }

    process {
        foreach ($Target in $MacAddress) {
            $ResolvedMac = $null
            if ($LookupTable.ContainsKey($Target)) {
                $ResolvedMac = $LookupTable[$Target]
                Write-Verbose "Resolved alias '$Target' to MAC address '$ResolvedMac'"
            }
            else {
                $ResolvedMac = $Target
            }

            # Validate the MAC address string
            if ($ResolvedMac -match '^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$') {
                # Convert the MAC address string to a byte array.
                $MacByteArray = ($ResolvedMac -split '[:-]') | ForEach-Object { [byte]('0x' + $_) }

                # Construct the magic packet: 6 bytes of 0xFF followed by 16 repetitions of the MAC address.
                $MagicPacket = [byte[]](, 0xFF * 6) + ($MacByteArray * 16)

                # Send the packet.
                $UdpClient.Send($MagicPacket, $MagicPacket.Length, $IPEndPoint) | Out-Null
                Write-Verbose "Sent WOL packet to $ResolvedMac"
            }
            else {
                Write-Warning "Invalid MAC address or alias specified: '$Target'"
            }
        }
    }

    end {
        if ($UdpClient) {
            $UdpClient.Close()
            $UdpClient.Dispose()
        }
    }
}

Export-ModuleMember -Function 'Invoke-WakeOnLan'