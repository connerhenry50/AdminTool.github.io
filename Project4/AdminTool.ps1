Import-Module ActiveDirectory
Import-Module VMWare.VimAutomation
Import-Module VMware.Hv.Helper
Add-Type -AssemblyName PresentationFramework
$MainXAMLPath           = "C:\Users\rchenry\Documents\Projects\DemoApp\MainWindow.xaml"
$ConfigPath             = "C:\Users\rchenry\Documents\Projects\DemoApp\config.json"
[xml]$MainXAML          = Get-Content $MainXAMLPath
$MainXAMLReader         = New-Object System.Xml.XmlNodeReader $MainXAML
$MainWindow             = [Windows.Markup.XamlReader]::Load($MainXAMLReader)
$config                 = Get-Content -Path $configPath -Raw | ConvertFrom-Json
$hv_servers             = $config.HV_Servers
$vi_servers             = $config.VI_Servers


#--------------------------------- Functions -------------------------------
function Get_Credentials {
    try {
        if (-not $script:admin.password -or -not $script:admin.username){
            $credential = Get-Credential
            $script:admin = [pscustomobject]@{
                username = $credential.UserName
                password = (New-Object PSCredential 0, $credential.Password).GetNetworkCredential().Password
            }
        }
    }
    catch {}
}
function Confirm_Action {
    param([string]$Title,[string]$Message)
    $confirmation = [System.Windows.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    return $confirmation
}
#----------------------------------------------- AD Users -------------------------------------
$ADUser_list            = $MainWindow.FindName("ADUser_list")
$PassPreview_txtbx      = $MainWindow.FindName("PassPreview_txtbx")
$SetPass_txtbx          = $MainWindow.FindName("SetPass_txtbx")
$PreviewPass_btn        = $MainWindow.FindName("PreviewPass_btn")
$CopyPass_btn           = $MainWindow.FindName("CopyPass_btn")
$UserSetPass_btn        = $MainWindow.FindName("UserSetPass_btn")
$PasswordOptions_dock   = $MainWindow.FindName("PasswordOptions_dock")
$UserExpirePass_btn     = $MainWindow.FindName("UserExpirePass_btn")
$ADUserListRefresh_btn  = $MainWindow.FindName("ADUserListRefresh_btn")
$UserUnlock_btn         = $MainWindow.FindName("UserUnlock_btn")
$UserDisable_btn        = $MainWindow.FindName("UserDisable_btn")
$UserEnable_btn         = $MainWindow.FindName("UserEnable_btn")
$ADUserSearch_txtbx     = $MainWindow.FindName("ADUserSearch_txtbx")
$FilterPanelExpand_btn  = $MainWindow.FindName("FilterPanelExpand_btn")
$FilterPanel_stckpnl    = $MainWindow.FindName("FilterPanel_stckpnl")
$SelectedUser_txtbx     = $MainWindow.FindName("SelectedUser_txtbx")
$FilterADLocked_cb      = $MainWindow.FindName("FilterADLocked_cb")
$FilterADDisabled_cb    = $MainWindow.FindName("FilterADDisabled_cb")
$FilterADExpired_cb     = $MainWindow.FindName("FilterADExpired_cb")
function Get_ADUsers {  
    $UserExclusions = $config.User_Exclusions

    $script:ADUsers = Get-ADUser -Filter * -Properties * |
        Where-Object {
            $_.SamAccountName -notin $UserExclusions
        }
}
function Get_ADUserstatus {
    $now = Get-Date
    $ADUserStatusList = $script:ADUsers | ForEach-Object {
        $statusList = @()
        if ($_.LockedOut) { $statusList += "Locked" }
        if (-not $_.Enabled) { $statusList += "Disabled" }
        if ($_.AccountExpirationDate -and $_.AccountExpirationDate -lt $now) { $statusList += "Expired" }
        if ($_.PasswordExpired) { $statusList += "PasswordExpired" }

        [PSCustomObject]@{
            Name = $_.Name
            Status = $statusList -join ", "
            SamAccountName = $_.SamAccountName
        }
    }
    $script:ADUserStatus = [System.Windows.Data.CollectionViewSource]::GetDefaultView(@($ADUserStatusList))
}
function Search_ADUsers {
    $searchText = $ADUserSearch_txtbx.Text.Trim().ToLower()
    $filteredSource = $script:ADUserStatus | Where-Object {
        if (-not [string]::IsNullOrWhiteSpace($searchText)) {
            $fields = @($_.Name, $_.Status, $_.SamAccountName)
            return $fields | Where-Object { $_ -and $_.ToString().ToLower().Contains($searchText) }
        }
        return $true
    }

    $ADUser_list.ItemsSource = [System.Windows.Data.CollectionViewSource]::GetDefaultView(@($filteredSource))
}
function Unlock_SelectedUser {
    param ([string]$selectedUser)
        Unlock-ADAccount -Identity $selectedUser
        [System.Windows.MessageBox]::Show("$selectedUser Unlocked")
}
function Expire_SelectedUser {
    param ([string]$selectedUser)
    $confirm = Confirm_Action -Title "Expire Password?" -Message "Are you sure you want to expire the password for '$($selectedUser.Name)'?"

    if ($confirm -eq "Yes") {
        Set-ADUser -Identity $selectedUser -ChangePasswordAtLogon $true
        [System.Windows.MessageBox]::Show("Password for $($selectedUser.Name) set to expire at next logon.")
    }
}
function Disable_SelectedAccount {
    param ([string]$selectedAccount)
    $confirm = Confirm_Action -Title "Disable Account?" -Message "Are you sure you want to disable '$($selectedAccount)'?"
    if ($confirm -eq "Yes") {
        Disable-ADAccount -Identity $SelectedAccount
        [System.Windows.MessageBox]::Show("$SelectedAccount set to disabled.")
    }
}
function Enable_SelectedAccount {
    param ([string]$selectedAccount)
    $confirm = Confirm_Action -Title "Enable Account?" -Message "Are you sure you want to enable '$($selectedAccount)'?"
    if ($confirm -eq "Yes") {
        Enable-ADAccount -Identity $SelectedAccount
        [System.Windows.MessageBox]::Show("$SelectedAccount set to enabled.")
    }
}
function Set_SelectedUserPass {
    param ([string]$SelectedUser)
    $password = $SetPass_txtbx.Password
    $confirm = Confirm_Action -Title "Reset Password?" -Message "Reset password for '$($SelectedUser)'?"

    if ($confirm -eq "Yes") {
        Set-ADAccountPassword -Identity $SelectedUser -Reset -NewPassword (ConvertTo-SecureString $password -AsPlainText -Force)
        [System.Windows.MessageBox]::Show("Password for $(SelectedUser) has been reset. Make sure to expire if you want to change it at next logon.")
    }
}
function Update_FilteredUserList {
    $showLocked   = $FilterADLocked_cb.IsChecked
    $showExpired  = $FilterADExpired_cb.IsChecked
    $showDisabled = $FilterADDisabled_cb.IsChecked
    if (-not ($showLocked -or $showExpired -or $showDisabled)) {
        $ADUser_list.ItemsSource = $script:ADUserStatus
        return
    }
    $filtered = $script:ADUserStatus | Where-Object {
        ($showLocked   -and $_.Status -Like '*Locked*')   -or
        ($showExpired  -and $_.Status -Like '*Expired*')  -or
        ($showDisabled -and $_.Status -Like '*Disabled*')
    }
    $ADUser_list.ItemsSource = [System.Windows.Data.CollectionViewSource]::GetDefaultView(@($filtered))
}
$FilterPanelExpand_btn.Add_Click({
    switch ($FilterPanel_stckpnl.Visibility) {
        "Collapsed" {
            $FilterPanel_stckpnl.Visibility = "Visible"
            $FilterPanelExpand_btn.Content   = ". . ."
        }
        "Visible" {
            $FilterPanel_stckpnl.Visibility = "Collapsed"
            $FilterPanelExpand_btn.Content   = "Filter"
        }
    }
})
$FilterADLocked_cb.Add_Checked({
    Update_FilteredUserList
})
$FilterADLocked_cb.Add_Unchecked({    
    Update_FilteredUserList
})
$FilterADExpired_cb.Add_Checked({    
    Update_FilteredUserList
})
$FilterADExpired_cb.Add_Unchecked({    
    Update_FilteredUserList
})
$FilterADDisabled_cb.Add_Checked({     
    Update_FilteredUserList
})
$FilterADDisabled_cb.Add_Unchecked({     
    Update_FilteredUserList
})
$ADUserSearch_txtbx.Add_TextChanged({
    Search_ADUsers
})
$UserUnlock_btn.Add_Click({
    Unlock_SelectedUser($ADUser_list.SelectedItem.SamAccountName)
})
$UserExpirePass_btn.Add_Click({
    Expire_SelectedUser($ADUser_list.SelectedItem.SamAccountName)

})
$UserSetPass_btn.Add_Click({
    if($null -eq $SetPass_txtbx.Password.Trim()){
        [System.Windows.MessageBox]::Show("No password entered.")
    } else {
        Set_SelectedUserPass($ADUser_list.SelectedItem.SamAccountName)
    }
})
$UserDisable_btn.Add_Click({
    Disable_SelectedAccount($ADUser_list.SelectedItem.SamAccountName)
})
$UserEnable_btn.Add_Click({
    Enable_SelectedAccount($ADUser_list.SelectedItem.SamAccountName)
})
$ADUserListRefresh_btn.Add_Click({
    Get_ADUsers
    Get_ADUserstatus
    $ADUser_list.ItemsSource = $script:ADUserStatus
    $FilterADLocked_cb.IsChecked = "False"
    $FilterADExpired_cb.IsChecked = "False"
    $FilterADDisabled_cb.IsChecked = "False"
})
$ADUser_list.Add_SelectionChanged({
    $SelectedUser_txtbx.Text = $ADUser_List.SelectedItem.Name
})
$PreviewPass_btn.Add_PreviewMouseLeftButtonDown({
    $PassPreview_txtbx.text = $SetPass_txtbx.Password
    $SetPass_txtbx.Visibility = [System.Windows.Visibility]::Collapsed
    $PassPreview_txtbx.Visibility = [System.Windows.Visibility]::Visible
    $PassPreview_txtbx.Width = ($PassPreview_txtbx.Text.Length * $PassPreview_txtbx.FontSize) * 0.55
})
$PreviewPass_btn.Add_PreviewMouseLeftButtonUp({
    $PassPreview_txtbx.Text = ""
    $SetPass_txtbx.Visibility = [System.Windows.Visibility]::Visible
    $PassPreview_txtbx.Visibility = [System.Windows.Visibility]::Collapsed
    [System.Windows.Controls.Panel]::SetZIndex($PassPreview_txtbx, 0)
})
$CopyPass_btn.Add_Click({
    $Password = $SetPass_txtbx.Password
    [System.Windows.Clipboard]::SetText($Password)
})
$ADUser_list.Add_SelectionChanged({
    $script:SelectedADUser = $ADUser_list.SelectedItem.SamAccountName
    $PasswordOptions_dock.Visibility = "Visible"
    $Enabled = (Get-ADUser -Identity $SelectedUser | Select-Object Enabled).Enabled
        if($Enabled){
            $UserDisable_btn.Visibility   = "Visible"
            $UserEnable_btn.Visibility    = "Collapsed"
        } else {
            $UserDisable_btn.Visibility   = "Collapsed"
            $UserEnable_btn.Visibility    = "Visible"
        }
    $Locked = (Get-ADUser -Identity $SelectedUser | Select-Object LockedOut).LockedOut
    if($Locked){
        $UserDisable_btn.Visibility   = "Visible"
        $UserEnable_btn.Visibility    = "Collapsed"
    } else {
        $UserDisable_btn.Visibility   = "Collapsed"
        $UserEnable_btn.Visibility    = "Visible"
    }
})
#-------------------------------------------------------- AD Computers ---------------------------------------
$ADComputerSearch_txtbx = $MainWindow.FindName("ADComputerSearch_txtbx")
$AllADComp_Dgrid        = $MainWindow.FindName("AllADComp_Dgrid")
$RefreshComputerList_btn= $MainWindow.FindName("RefreshComputerList_btn")
$DiscoADComputer_btn    = $MainWindow.FindName("DiscoADComputer_btn")
$RDPComputer_btn        = $MainWindow.FindName("RDPComputer_btn")
$RemoteAssistAD_btn     = $MainWindow.FindName("RemoteAssistAD_btn")
$ShutdownPC_btn         = $MainWindow.FindName("ShutdownPC_btn")
$RestartPC_btn          = $MainWindow.FindName("RestartPC_btn")
$DisableADComputer_btn  = $MainWindow.FindName("DisableADComputer_btn")
$EnableADComputer_btn   = $MainWindow.FindName("EnableADComputer_btn")
$SelectedADPCUser_txtbx = $MainWindow.FindName("SelectedADPCUser_txtbx")
$SelectedADPCName_txtbx = $MainWindow.FindName("SelectedADPCName_txtbx")
function Get_ADComputers {
    $ComputerExclusions = $config.Computer_Exclusions
    $OUExclusions = $config.OU_Exclusions
    
    $ADComputerList = Get-ADComputer -Filter * -Properties IPv4Address, OperatingSystem, Description, DistinguishedName |
        Where-Object {
            $_.Name -and ($_.Name -notin $ComputerExclusions)
        } | ForEach-Object {
            $OUs = ($_.DistinguishedName -split ',') |
                Where-Object { $_ -like 'OU=*' } |
                ForEach-Object { $_ -replace '^OU=' } |
                Where-Object { $_ -and ($_ -notin $OUExclusions) }

            [pscustomobject]@{
                Name             = $_.Name
                IPv4Address      = $_.IPv4Address
                OperatingSystem  = $_.OperatingSystem
                Description      = $_.Description
                OU               = $OUs -join "`n"
            }
        }
    $script:ADComputers = [System.Windows.Data.CollectionViewSource]::GetDefaultView(@($ADComputerList))
}
function Search_ADComputers {
    $searchText = $ADComputerSearch_txtbx.Text.Trim().ToLower()

    if (-not [string]::IsNullOrWhiteSpace($searchText)) {
        $filteredSource = $script:ADComputers | Where-Object {
            ($_.Name -and $_.Name.ToString().ToLower().Contains($searchText)) -or
            ($_.IPv4Address -and $_.IPv4Address.ToString().ToLower().Contains($searchText)) -or
            ($_.OperatingSystem -and $_.OperatingSystem.ToString().ToLower().Contains($searchText)) -or
            ($_.Description -and $_.Description.ToString().ToLower().Contains($searchText)) -or
            ($_.OU -and $_.OU.ToString().ToLower().Contains($searchText))
        }
    } else {
        $filteredSource = $script:ADComputers
    }
    $AllADComp_Dgrid.ItemsSource = [System.Windows.Data.CollectionViewSource]::GetDefaultView(@($filteredSource))
}
function Get_ActiveUser {
    param([string]$ComputerName)

    $lines = query user /server:$ComputerName 2>$null
    foreach ($line in $lines) {
        if ($line -match '^\s*USERNAME\s+SESSIONNAME') { continue }
            $parts = $line -split '\s{2,}'
            if ($parts[3] -eq "Active") {
                return  [pscustomobject]@{
                    Name = $parts[0].Trim()
                    Session = $parts[1]
                }
            }
    } return "No Active Session"
}
function Disconnect_ActiveUser {
    param ([string]$SelectedComputer)
    $Session = (Get_ActiveUser($SelectedComputer)).Session
    logoff $Session /server:$SelectedComputer
}
function Send_RemAssist {
    param ([string]$SelectedComputer)
    msra /offerra $SelectedComputer
   $logPath = "V:\RemoteAssist\remote assistance log.txt"
    $logLine = "$env:USERNAME, $SelectedComputer, $(Get-Date -Format 'HH:mm:ss.ff'), $(Get-Date -Format 'ddd MM/dd/yyyy')"
    Add-Content -Path $logPath -Value $logLine 
}
#----------------------------------------- AD Computers --------------------------
$RefreshComputerList_btn.Add_Click({
    Get_ADComputers
    $AllADComp_Dgrid.ItemsSource = $script:ADComputers
})
$ADComputerSearch_txtbx.Add_TextChanged({
    Search_ADComputers
})
$DiscoADComputer_btn.Add_Click({
    Disconnect_ActiveUser -ComputerName $script:SelectedADComputer
})
$RemoteAssistAD_btn.Add_Click({
    Send_RemAssist -ComputerName $script:SelectedADComputer
})
$ShutdownPC_btn.Add_Click({
    Stop_Computer -ComputerName $script:SelectedADComputer
})
$RestartPC_btn.Add_Click({
    Restart_Computer -ComputerName $script:SelectedADComputer
})
$DisableADComputer_btn.Add_Click({
    Disable_SelectedAccount -selectedAccount $script:SelectedADComputer
})
$EnableADComputer_btn.Add_Click({
    Enable_SelectedAccount -selectedAccount $script:SelectedADComputer

})

$AllADComp_Dgrid.Add_SelectionChanged({
    $script:SelectedADComputer = $AllADComp_Dgrid.SelectedItem.Name
    $SelectedADPCName_txtbx.Text = $script:SelectedADComputer
    if($script:SelectedADComputer){
        $ShutdownPC_btn.Visibility              = "Visible"
        $RestartPC_btn.Visibility               = "Visible"
        $Enabled = (Get-ADComputer -Identity $script:SelectedADComputer | Select-Object Enabled).Enabled
        if($Enabled){
            $DisableADComputer_btn.Visibility   = "Visible"
            $EnableADComputer_btn.Visibility    = "Collapsed"
        } else {
            $DisableADComputer_btn.Visibility   = "Collapsed"
            $EnableADComputer_btn.Visibility    = "Visible"
        }
        $SelectedADPCUser_txtbx.Text = (Get_ActiveUser($script:SelectedADComputer)).Name
        if(-not $SelectedADPCUser_txtbx.Text -eq ""){
            $DiscoADComputer_btn.Visibility     = "Visible"
            $RemoteAssistAD_btn.Visibility      = "Visible"
            $RDPComputer_btn.Visibiibility      = "Collapsed"
            $RemoteAssistAD_btn.Visibility      = "Collapsed"
            $RDPComputer_btn.Visibility         = "Visible"
        }
    } else {
        $DiscoADComputer_btn.Visibility         = "Collapsed"
        $RDPComputer_btn.Visibility             = "Collapsed"
        $RemoteAssistAD_btn.Visibility          = "Collapsed"
        $ShutdownPC_btn.Visibility              = "Collapsed"
        $RestartPC_btn.Visibility               = "Collapsed"
        $DisableADComputer_btn.Visibility       = "Collapsed"
        $EnableADComputer_btn.Visibility        = "Collapsed"
    }
})
#------------------------------------------------ VM ------------------------------------------------
$RefreshVMList_btn      = $MainWindow.FindName("RefreshVMList_btn")
$AllVMComp_Dgrid        = $MainWindow.FindName("AllVMComp_Dgrid")
$VMSearch_txtbx         = $MainWindow.FindName("VMSearch_txtbx")
$SelectedVMUser_cmbbx   = $MainWindow.FindName("SelectedVMUser_cmbbx")
$SelectedVMName_cmbbx   = $MainWindow.FindName("SelectedVMName_cmbbx")
$DiscoVMComputer_btn    = $MainWindow.FindName("DiscoVMComputer_btn")
$RemoteAssistVM_btn     = $MainWindow.FindName("RemoteAssistVM_btn")
$ShutdownVM_btn         = $MainWindow.FindName("ShutdownVM_btn")
$RestartVM_btn          = $MainWindow.FindName("RestartVM_btn")
$StartupVM_btn          = $MainWindow.FindName("StartupVM_btn")
$UnassignVM_btn         = $MainWindow.FindName("UnassignVM_btn")
$AssignVM_btn           = $MainWindow.FindName("AssignVM_btn")
$FilterVMServ_stckpnl   = $MainWindow.FindName("FilterVMServ_stckpnl")
$FilterVMServ_btn       = $MainWindow.FindName("FilterVMServ_btn")
$ConnectedVMUser_txtbx  = $MainWindow.FindName("ConnectedVMUser_txtbx")
function Connect_VIServers {
    Write-Host "Connecting to VIServers"
    if(-not $serverlist -eq $null){Disconnect-VIServer * -Confirm:$false}
    foreach ($viServer in $vi_servers) {
        try {
            $connectedServer = Connect-VIServer $viServer -UserName $admin.username -Password $admin.password -ErrorAction Stop
            if ($connectedServer) {
                Write-Host "Credentials checked, successful permissions."
                return  
            }
        }
        catch {
            Write-Warning "Failed to connect to $viServer. Check your entered credentials and make sure you have permissions for access."
            pause
            break
        }
    }
    Write-Error "Could not connect to any vCenter server. Exiting..."
    exit
}
function Get_VMEntitled {
    $entitledUsers = @()
    foreach ($server in $hv_servers) {
        Connect-HVServer -Server $server -UserName $admin.username -Password $admin.password | Out-Null
        $pools = Get-HVPool -ErrorAction SilentlyContinue
        foreach ($pool in $pools) {
            $poolName = $pool.base.name
            try {
                $poolEntitlements = Get-HVEntitlement -ResourceType Desktop -ResourceName $poolName -ErrorAction SilentlyContinue
                foreach ($ent in $poolEntitlements) {
                    $entitledUsers += $ent.base.loginname
                }
            } catch {}
        }
        Disconnect-HVServer -Server $server -Confirm:$false   
    }
    return $entitledUsers | Select -Unique
}
function Filter_VMGrid {
    $SelectedServers = $script:ServerCheckBoxes | Where-Object { $_.IsChecked -eq $true } | ForEach-Object { $_.Tag }
    $filtered = $script:VMList | Where-Object {
        if ($SelectedServers.Count -gt 0) {
            return $SelectedServers -contains $_.Server
        }
        return $true
    }
    $AllVMComp_Dgrid.ItemsSource = [System.Windows.Data.CollectionViewSource]::GetDefaultView(@($filtered))
}
function Search_VMGrid {
    $searchText = $VMSearch_txtbx.Text.Trim().ToLower()
    $filteredSource = $script:VMList | Where-Object {
        if (-not [string]::IsNullOrWhiteSpace($searchText)) {
            $fields = @($_.MachineName, $_.DisplayName, $_.SamAccountName, $_.Server)
            return $fields | Where-Object { $_ -and $_.ToString().ToLower().Contains($searchText) }
        }
        return $true
    }
    $AllVMComp_Dgrid.ItemsSource = [System.Windows.Data.CollectionViewSource]::GetDefaultView(@($filteredSource))
}
function Get_VMList {
    Get_Credentials
    if (-not $script:admin.password -or -not $script:admin.username){
        return
    }
    Get_ADUsers
    $script:VMList = @()
    foreach ($server in $hv_servers) {
        try {
            $connectedServer = Connect-HVServer $server -UserName $admin.username -Password $admin.password | Out-Null
            if ($connectedServer) {
            }
        }
        catch {
            continue
        }
        $machineSummaries = Get-HVMachineSummary
        foreach ($summary in $machineSummaries) {
            $machineName = $summary.base.Name
            if ($summary.namesdata -and $summary.namesdata.Count -gt 0) {
                foreach ($userEntry in $summary.namesdata) {
                    $fullUsername = $userEntry.Username

                    if ($fullUsername) {
                        $SamAccount = $fullUsername.Split('\')[1]
                        $ADUser = Get-ADUser -Filter { SamAccountName -eq $SamAccount } -Properties DisplayName, SamAccountName
                        $script:VMList += [PSCustomObject]@{
                            MachineName    = $machineName
                            DisplayName    = if ($ADUser) { $ADUser.DisplayName } else { "Not Assigned" }
                            SamAccountName = if ($ADUser) { $ADUser.SamAccountName } else { $SamAccount }
                            Server         = $server  
                        }
                    }
                    else {
                        $script:VMList += [PSCustomObject]@{
                            DisplayName    = "Not Assigned"
                            SamAccountName = "NA"
                            MachineName    = $machineName
                            Server         = $server
                        }
                    }
                }
            }
            else {
                $script:VMList += [PSCustomObject]@{
                    DisplayName    = "Not Assigned"
                    SamAccountName = "NA"
                    MachineName    = $machineName
                    Server         = $server
                }
            }
        }
        Disconnect-HVServer * -Confirm:$false
    }
    $NotAssignedEntitled = Get_VMEntitled | Where-Object {
        $_ -notin $script:VMList.SamAccountName
    }
    foreach ($SamAccount in $NotAssignedEntitled) {
        $DisplayName = $script:ADUsers | Where-Object { $_.SamAccountName -eq $SamAccount }
        $script:VMList += [PSCustomObject]@{
            DisplayName     = $DisplayName.DisplayName
            SamAccountName  = $SamAccount
            MachineName     = "Not Assigned"
            Server          = "NA"
        }
    }
    $SelectedVMUser_cmbbx.Items.Clear()
    $SelectedVMName_cmbbx.Items.Clear()
    $allUsers = $script:VMList |
        Where-Object { $null -ne $_.SamAccountName -and $_.SamAccountName -ne "" -and $_.SamAccountName -ne "NA" } |
        Select-Object -ExpandProperty SamAccountName -Unique |
        Sort-Object

    foreach ($user in $allUsers) {
        $SelectedVMUser_cmbbx.Items.Add($user)
    }
    $allMachines = $script:VMList |
        Where-Object {$null -ne $_.MachineName -and $_.MachineName -ne "" -and $_.MachineName -ne "Not Assigned" } |
        Select-Object -ExpandProperty MachineName -Unique |
        Sort-Object

    foreach ($vm in $allMachines) {
        $SelectedVMName_cmbbx.Items.Add($vm)
    }
}
function Start_VM {
    param([string]$machine)
    Start-VM -VM $machine -Confirm:$false
}
function Stop_VM {
    param([string]$machine)
    Stop-VM -VM $machine -confirm:$false
}
function Get_State {
    param($machine)
    return Get-HVMachineSummary -MachineName $machine | Select-Object -ExpandProperty Base | Select-Object -ExpandProperty BasicState
}
function Restart_VM {
    param([string]$machine,[string]$server)
    Connect-HVServer $server -UserName $admin.username -Password $admin.password
    $Status = Get_State -machine $machine
    if($Status -notlike "UNAVAILABLE" -or $Status -notlike "AGENT_UNREACHABLE"){
        Restart-HVMachine -MachineName $machine -Confirm:$false
    } Else {
        Start_VM($machine)
        return
    }

    while ($Status -notlike "AVAILABLE") {
        $Status = Get_State -machine $machine
        Clear-Host
        Write-Host("Waiting for Unavailable, currently: $Status") -NoNewline
        Start-Sleep -Milliseconds 2000
    }
    while ($Status -notlike "AGENT_UNREACHABLE") {
        $Status = Get_State -machine $machine
        Clear-Host
        Write-Host("Waiting for Available, currently: $Status") -NoNewline
        Start-Sleep -Milliseconds 2000
    }
    Write-Host("Done")
    Disconnect-HVServer * -Confirm:$false
}
function Unassign_VM {
    param ([string]$machine, [string]$server)
    $connection = Connect-HVServer -Server $server -UserName $admin.username -Password $admin.password
    $services1=$connection.extensiondata
    $machineid=(get-hvmachine -machinename $machine).id
    $machineservice=new-object vmware.hv.machineservice
    $machineinfohelper=$machineservice.read($services1, $machineid)
    $machineinfohelper.getbasehelper().setuser($null)
    $machineservice.update($services1, $machineinfohelper)
    Disconnect-HVServer * -Confirm:$false
}
function Assign_VM {
    param([string]$machine,[string]$user, [string]$server)
    get-hvmachine -MachineName $machine -HvServer $script:SelectedVMServer $machine | Set-HVMachine -User $hv_servers[0].Substring($hv_servers[0].IndexOf("."))+"\"+$user
}
#---------------------------------------- VM --------------------------------------------------------------------------------
$FilterVMServ_btn.Add_Click({
    switch ($FilterVMServ_stckpnl.Visibility) {
        "Collapsed" {
            $FilterVMServ_stckpnl.Visibility = "Visible"
            $FilterVMServ_btn.Content   = ". . ."
        }
        "Visible" {
            $FilterVMServ_stckpnl.Visibility = "Collapsed"
            $FilterVMServ_btn.Content   = "Filter"
        }
    }
})
$RefreshVMList_btn.Add_Click({
    Connect_VIServers
    Get_VMList
    $script:ServerCheckBoxes = @()
    $FilterVMServ_stckpnl.Children.Clear()
    $AllVMComp_Dgrid.ItemsSource = $null
    $AllVMComp_Dgrid.ItemsSource = $script:VMList
    $script:VMList | Where-Object { $_.Server } | Select-Object -ExpandProperty Server -Unique | Sort-Object | ForEach-Object {
        $server = $_
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = $server
        $cb.Tag = $server
        $cb.MaxWidth = "45"

        $cb.Add_Checked({
            Filter_VMGrid
        })
        $cb.Add_Unchecked({
            Filter_VMGrid
        })
        $FilterVMServ_stckpnl.Children.Add($cb) | Out-Null
        $script:ServerCheckBoxes += $cb
    }   
})
$AllVMComp_Dgrid.Add_SelectionChanged({
    $script:SelectedVMUser = $AllVMComp_Dgrid.SelectedItem.SamAccountName
    $script:SelectedVM = $AllVMComp_Dgrid.SelectedItem.MachineName
    $script:SelectedServer = $AllVMComp_Dgrid.SelectedItem.Server
    if ($script:SelectedVM) {
        $vmIndex = $SelectedVMName_cmbbx.Items.IndexOf($script:SelectedVM)
        if ($vmIndex -ge 0) { $SelectedVMName_cmbbx.SelectedIndex = $vmIndex }
    }
    if ($script:SelectedVMUser) {
        $userIndex = $SelectedVMUser_cmbbx.Items.IndexOf($script:SelectedVMUser)
        if ($userIndex -ge 0) { $SelectedVMUser_cmbbx.SelectedIndex = $userIndex }
    }
    $ConnectedVMUser_txtbx.Text = (Get_ActiveUser($script:SelectedVM)).Name
    
})

$VMSearch_txtbx.Add_TextChanged({
    Search_VMGrid
})
$DiscoVMComputer_btn.Add_Click({
    $script:SelectedVM
    Disconnect_ActiveUser -SelectedComputer $script:SelectedVM
})
$RemoteAssistVM_btn.Add_Click({
    Send_RemAssist -SelectedComputer $script:SelectedVM
})
$ShutdownVM_btn.Add_Click({
    Stop_VM -machine $script:SelectedVM
})
$RestartVM_btn.Add_Click({
    Restart_VM -machine $script:SelectedVM -server $script:SelectedServer
})
$StartupVM_btn.Add_Click({
    Start_VM -machine $script:SelectedVM
})
$UnassignVM_btn.Add_Click({
    Unassign_VM -machine $script:SelectedVM -server $script:SelectedServer
})
$AssignVM_btn.Add_Click({
    $AssignedMachine = $SelectedVMName_cmbbx.SelectedItem
    $AssignedUser = $SelectedVMUser_cmbbx.SelectedItem
    $AssignedMachineServer = $script:VMList | Where-Object { $_.MachineName -like $AssignedMachine } | Select-Object Server
    Assign_VM -machine $AssignedMachine -server $AssignedMachineServer -User $AssignedUser
})
#--------------- EVENT HANDLERS ----------------------------------------




$MainWindow.Add_Closing({
    try{
        Disconnect-VIServer * -Confirm:$false
    } catch{continue}
    
	close
})

$MainWindow.ShowDialog() | Out-Null
