﻿function Invoke-SNMPv3Set
{
<#

.SYNOPSIS

    Update information on network devices using SNMP SET requests.

.DESCRIPTION

    Function supports SNMPv3 with security levels noAuthNoPriv, authNoPriv and authPriv.
    Based on SnmpSharpNet - SNMP Library for C# (http://www.snmpsharpnet.com/) 

.PARAMETER UserName

    Username to use when updating information.

.PARAMETER Target

    SNMP Agent you want to connect to. Accepts IP address or host name.

.PARAMETER OID

    Object Identifier of the value to set.

.PARAMETER Type

    Data type of the value to set. The following data types are valid:

    Integer, Unsigned, String, HexString, DecimalString, NullObject, ObjectIdentifier, TimeTicks, IPAddress

.PARAMETER Value

    The value you want to set.

.PARAMETER AuthType

    Allowed authentication types are None, MD5 and SHA1. Defaults to None.

.PARAMETER AuthSecret

    Authentication password used for security level authNoPriv and authPriv.

.PARAMETER PrivType

    Allowed encryption types are None, DES, TripleDES, AES128, AES192 and AES256. Defaults to None.

.PARAMETER PrivSecret

    Encryption password used for security level authPriv.

.PARAMETER Context

    Context to use.

.PARAMETER Port

    UDP port to use when connecting to the SNMP Agent. Defaults to 161.

.PARAMETER Timeout

    Timeout in milliseconds when connecting to SNMP Agent. Defaults to 3000.

.PARAMETER Retry

    Number of retries if connection fails. Defaults to 1.

.EXAMPLE

    PS> Invoke-SNMPv3Set -UserName usr-none-none -Target demo.snmplabs.com -OID 1.3.6.1.2.1.1.5.0 -Type OctetString -Value SysName

    Node           OID               Type        Value
    ----           ---               ----        -----
    104.236.166.95 1.3.6.1.2.1.1.5.0 OctetString SysName

#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String]$UserName,

        [Parameter(Mandatory=$true)]
        [String]$Target,

        [Parameter(Mandatory=$true)]
        [String]$OID,

        [Parameter(Mandatory=$true)]  
        [ValidateSet('Integer', 'Unsigned', 'String', 'HexString', 'DecimalString', 'NullObject', 'ObjectIdentifier', 'TimeTicks', 'IPAddress')]
        [String]$Type,

        [Parameter(Mandatory=$true)]
        [Object]$Value,

        [Parameter(Mandatory=$false)]
        [ValidateSet('None', 'MD5', 'SHA1')]
        [String]$AuthType = 'None',

        [Parameter(Mandatory=$false)]
        [String]$AuthSecret,

        [Parameter(Mandatory=$false)]
        [ValidateSet('None', 'DES', 'TripleDES', 'AES128', 'AES192', 'AES256')]
        [String]$PrivType = 'None',

        [Parameter(Mandatory=$false)]
        [String]$PrivSecret,

        [Parameter(Mandatory=$false)]
        [String]$Context,

        [Parameter(Mandatory=$false)]
        [int]$Port = 161,

        [Parameter(Mandatory=$false)]
        [int]$Timeout = 3000,

        [Parameter(Mandatory=$false)]
        [int]$Retry = 1
    )

    process
    {
    
        $IPAddress = [System.Net.Dns]::GetHostEntry($Target).AddressList[0]
        $UdpTarget = [SnmpSharpNet.UdpTarget]::new($IPAddress, $Port, $Timeout, $Retry)
        $Params = [SnmpSharpNet.SecureAgentParameters]::new()

        if (-not $UdpTarget.Discovery($Params))
        {
            Write-Error 'Discovery failed. Unable to continue...'
            $UdpTarget.Close()
            return
        }

        if ($AuthType -ne 'None' -and $AuthSecret -and $PrivType -ne 'None' -and $PrivSecret)
        {
            Write-Verbose 'Security Level: authPriv'
            $Params.authPriv($UserName,
                [SnmpSharpNet.AuthenticationDigests]::$AuthType, $AuthSecret,
                [SnmpSharpNet.PrivacyProtocols]::$PrivType, $PrivSecret)
        }
        elseif ($AuthType -ne 'None' -and $AuthSecret -and $PrivType -eq 'None' -and (-not $PrivSecret))
        {
            Write-Verbose 'Security Level: authNoPriv'
            $Params.authNoPriv($UserName,
                [SnmpSharpNet.AuthenticationDigests]::$AuthType, $AuthSecret) 
        }
        elseif ($AuthType -eq 'None' -and (-not $AuthSecret) -and $PrivType -eq 'None' -and (-not $PrivSecret))
        {
            Write-Verbose 'Security Level: noAuthNoPriv'
            $Params.noAuthNoPriv($UserName)
        }
        else
        {
            Write-Error 'Invalid security level. SNMPv3 supports the following security levels: noAuthNoPriv, authNoPriv, authPriv'
            exit
        }

        if ($Context)
        {
            $Params.ContextName.Set($Context)
        }

        Write-Verbose ('Context: {0}' -f $Params.ContextName)

        switch ($Type)
        {
            'Integer' { 
                $Data = [SnmpSharpNet.Integer32]::new([int32]::Parse($Value))
            }
            'Unsigned' {
                $Data = [SnmpSharpNet.UInteger32]::new([uint32]::Parse($Value))
            }
            'String' {
                $Data = [SnmpSharpNet.OctetString]::new($Value)
            }
            'HexString' {
                $HexString = $Value -replace '0x|\s'
                $Bytes = [byte[]]::new($HexString.Length / 2)
                for ($i = 0; $i -lt $HexString.Length; $i += 2){
                    $Bytes[$i/2] = [convert]::ToByte($HexString.Substring($i, 2), 16)
                }
                $Data = [SnmpSharpNet.OctetString]::new($Bytes)
            }
            'DecimalString' {
                [byte[]]$Bytes = $Value -split ' ' | foreach {[byte]$_}
                $Data = [SnmpSharpNet.OctetString]::new($Bytes)
            }
            'NullObject' {
                $Data = [SnmpSharpNet.Null]::new()
            }
            'ObjectIdentifier' {
                $Data = [SnmpSharpNet.Oid]::new($Value)
            }
            'TimeTicks' {
                $Data = [SnmpSharpNet.TimeTicks]::new([uint32]::Parse($Value))
            }
            'IPAddress' {
                $Data = [SnmpSharpNet.IpAddress]::new([IPAddress]::Parse($Value).GetAddressBytes())
            }
            default {
                Write-Warning "Unknown type string: $Type"
                return
            }
        }

        $Pdu = [SnmpSharpNet.Pdu]::new()
        $Pdu.Type = [SnmpSharpNet.PduType]::Set
        $Pdu.VbList.Add($OID, $Data)

        Write-Verbose ($Pdu.VbList | foreach {"Variable Binding: $_"})

        # Workaround because [SnmpSharpNet.SnmpConstants]::GetTypeName() gives the following error:
        # The field or property: "EnterpriseSpecific" for type: "SnmpSharpNet.SnmpConstants" differs only in letter casing 
        # from the field or property: "enterpriseSpecific". The type must be Common Language Specification (CLS) compliant.
        $GetTypeName = [SnmpSharpNet.SnmpConstants].GetMethod("GetTypeName") 

        try
        {
            $Result = $UdpTarget.Request($Pdu, $Params)
        }
        catch
        {
            Write-Warning "$Target`: $_"
            $Result = $null
        }

        if ($Result)
        {
            if ($Result.Pdu.Type -eq [SnmpSharpNet.PduType]::Report)
            {
                Write-Warning 'Report packet received.'
                $ErrStr = [SnmpSharpNet.SNMPV3ReportError]::TranslateError($Result)
                Write-Warning ('Error: {0}' -f $ErrStr)
                $UdpTarget.Close()
                return
            }

            if ($Result.Pdu.ErrorStatus -ne 0)
            {
                $ErrMsg = 'SNMP target has returned error code {0} on index {1}.' -f 
                    [SnmpSharpNet.SnmpError]::ErrorMessage($Result.Pdu.ErrorStatus),
                    $Result.Pdu.ErrorIndex
                Write-Warning $ErrMsg
                return
            }

            foreach ($Vb in $Result.Pdu.VbList)
            {
                [PSCustomObject] @{
                    Node  = $IPAddress
                    OID   = $Vb.Oid.ToString()
                    Type  = $GetTypeName.Invoke($null, $Vb.Value.Type)
                    Value = $Vb.Value.ToString()
                }
            }
        }
    }
}
