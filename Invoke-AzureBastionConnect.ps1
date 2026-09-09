function Invoke-AzureBastionConnect {
    param(
        [switch]$Console
    )

    $version = '1.4.0'

    # Rename the host window/tab so it is recognizable as a Bastion session.
    # Best-effort: some hosts (ISE, certain PowerShell terminals on Linux/macOS)
    # do not support setting RawUI.WindowTitle, so we guard with try/catch.
    try {
        if ($Host.UI -and $Host.UI.RawUI) {
            $Host.UI.RawUI.WindowTitle = "AzBastionConnect v$version"
        }
    }
    catch {
        # Window title is not supported by this host; ignore.
    }

    if ((az config get core.enable_broker_on_windows --only-show-errors | ConvertFrom-Json).value -eq 'true') {
        $text = 'From Azure CLI version 2.61.0, Web Account Manager (WAM) is the default authentication method on Windows.
It means the login window is a Windows component and not a browser window anymore.
If you prefer the browser login method, you can disable WAM with the following command:'
        $cmd = 'az account clear
az config set core.enable_broker_on_windows=false'

        Write-Host -ForegroundColor Yellow $text
        Write-Host $cmd
    }

    $azExtensions = @('bastion')

    $installedExtensions = az extension list --output json | ConvertFrom-Json
    $missingExtension = $false
    # Test if az extensions are installed
    foreach ($extension in $azExtensions) {
        if (-not ($installedExtensions | Where-Object { $_.name -eq $extension })) {
            $text = "The Azure CLI extension '$extension' is required for this script to work.
You can install it using the command:"

            Write-Host -ForegroundColor Yellow $text
            Write-Host "az extension add --name $extension"
            $missingExtension = $true
        }
    }

    if ($missingExtension) {
        Write-Host -ForegroundColor Yellow "`nPlease install the missing extensions and try again."
        return
    }

    # Check if azure cli is installed
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Write-Host -ForegroundColor Red 'Azure CLI is not installed. Please install it from https://aka.ms/installazurecli.'
        return
    }
    
    if ($Console) {
        function Select-ConsoleItem {
            param(
                [Parameter(Mandatory)]
                [object[]]$Items,

                [Parameter(Mandatory)]
                [string]$Title,

                [scriptblock]$DisplayItem = { param($Item) [string]$Item },

                [ValidateRange(3, 30)]
                [int]$MaxVisibleItems = 10,

                [switch]$Searchable
            )

            $Items = @($Items)
            if ($Items.Count -eq 0) {
                return $null
            }

            if ($Items.Count -eq 1) {
                return $Items[0]
            }

            $displayLabels = @(
                foreach ($item in $Items) {
                    [string](& $DisplayItem $item)
                }
            )
            $allItemIndexes = @(0..($Items.Count - 1))

            $canUseInteractiveMenu = $true
            try {
                if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
                    $canUseInteractiveMenu = $false
                }
                else {
                    $null = [Console]::WindowWidth
                    $null = [Console]::CursorTop
                }
            }
            catch {
                $canUseInteractiveMenu = $false
            }

            if ($canUseInteractiveMenu) {
                $filteredIndexes = @($allItemIndexes)
                $searchText = ''
                $selectedIndex = 0
                $firstVisibleIndex = 0
                $visibleItemCount = [Math]::Min($Items.Count, $MaxVisibleItems)
                $originalCursorVisible = $true
                $originalForegroundColor = [ConsoleColor]::Gray
                $originalBackgroundColor = [ConsoleColor]::Black
                $menuStarted = $false

                try {
                    Write-Host ''
                    Write-Host $Title -ForegroundColor Yellow
                    if ($Searchable) {
                        Write-Host 'All items are shown by default. Type to search, use the arrows, then press Enter.' -ForegroundColor Gray
                        $searchLineTop = [Console]::CursorTop
                        Write-Host ''
                    }
                    else {
                        Write-Host 'Use the Up and Down arrows, then press Enter. Press Escape to cancel.' -ForegroundColor Gray
                    }

                    for ($lineIndex = 0; $lineIndex -lt $visibleItemCount; $lineIndex++) {
                        Write-Host ''
                    }

                    $menuTop = [Console]::CursorTop - $visibleItemCount
                    $originalCursorVisible = [Console]::CursorVisible
                    $originalForegroundColor = [Console]::ForegroundColor
                    $originalBackgroundColor = [Console]::BackgroundColor
                    [Console]::CursorVisible = $false
                    $menuStarted = $true

                    while ($true) {
                        $resultCount = $filteredIndexes.Count
                        if ($resultCount -gt 0) {
                            if ($selectedIndex -lt $firstVisibleIndex) {
                                $firstVisibleIndex = $selectedIndex
                            }
                            elseif ($selectedIndex -ge ($firstVisibleIndex + $visibleItemCount)) {
                                $firstVisibleIndex = $selectedIndex - $visibleItemCount + 1
                            }
                        }
                        else {
                            $selectedIndex = 0
                            $firstVisibleIndex = 0
                        }

                        $consoleWidth = [Math]::Max(20, [Console]::WindowWidth - 1)
                        $maximumLabelLength = [Math]::Max(1, $consoleWidth - 4)

                        if ($Searchable) {
                            [Console]::SetCursorPosition(0, $searchLineTop)
                            $searchValue = if ([string]::IsNullOrEmpty($searchText)) { '<all>' } else { $searchText }
                            $searchLine = "Search: $searchValue  ($resultCount result(s))"
                            if ($searchLine.Length -gt $consoleWidth) {
                                $searchLine = $searchLine.Substring(0, [Math]::Max(1, $consoleWidth - 3)) + '...'
                            }

                            [Console]::BackgroundColor = $originalBackgroundColor
                            [Console]::ForegroundColor = [ConsoleColor]::Yellow
                            [Console]::Write($searchLine.PadRight($consoleWidth))
                        }

                        for ($lineIndex = 0; $lineIndex -lt $visibleItemCount; $lineIndex++) {
                            $filteredItemIndex = $firstVisibleIndex + $lineIndex
                            [Console]::SetCursorPosition(0, $menuTop + $lineIndex)

                            if ($filteredItemIndex -lt $resultCount) {
                                $itemIndex = $filteredIndexes[$filteredItemIndex]
                                $label = $displayLabels[$itemIndex]
                                if ($label.Length -gt $maximumLabelLength) {
                                    $label = $label.Substring(0, [Math]::Max(1, $maximumLabelLength - 3)) + '...'
                                }

                                $marker = if ($filteredItemIndex -eq $selectedIndex) { '>' } else { ' ' }
                                $line = "$marker $label".PadRight($consoleWidth)

                                if ($filteredItemIndex -eq $selectedIndex) {
                                    [Console]::BackgroundColor = [ConsoleColor]::DarkYellow
                                    [Console]::ForegroundColor = [ConsoleColor]::Black
                                }
                                else {
                                    [Console]::BackgroundColor = $originalBackgroundColor
                                    [Console]::ForegroundColor = $originalForegroundColor
                                }

                                [Console]::Write($line)
                            }
                            elseif ($Searchable -and $resultCount -eq 0 -and $lineIndex -eq 0) {
                                [Console]::BackgroundColor = $originalBackgroundColor
                                [Console]::ForegroundColor = [ConsoleColor]::Yellow
                                [Console]::Write('  No matching item.'.PadRight($consoleWidth))
                            }
                            else {
                                [Console]::BackgroundColor = $originalBackgroundColor
                                [Console]::ForegroundColor = $originalForegroundColor
                                [Console]::Write((' ' * $consoleWidth))
                            }
                        }

                        [Console]::BackgroundColor = $originalBackgroundColor
                        [Console]::ForegroundColor = $originalForegroundColor
                        [Console]::SetCursorPosition(0, $menuTop + $visibleItemCount)
                        $key = [Console]::ReadKey($true)
                        $searchChanged = $false

                        switch ($key.Key) {
                            'UpArrow' {
                                if ($resultCount -gt 0) {
                                    $selectedIndex = if ($selectedIndex -eq 0) {
                                        $resultCount - 1
                                    }
                                    else {
                                        $selectedIndex - 1
                                    }
                                }
                            }
                            'DownArrow' {
                                if ($resultCount -gt 0) {
                                    $selectedIndex = if ($selectedIndex -eq ($resultCount - 1)) {
                                        0
                                    }
                                    else {
                                        $selectedIndex + 1
                                    }
                                }
                            }
                            'PageUp' {
                                if ($resultCount -gt 0) {
                                    $selectedIndex = [Math]::Max(0, $selectedIndex - $visibleItemCount)
                                }
                            }
                            'PageDown' {
                                if ($resultCount -gt 0) {
                                    $selectedIndex = [Math]::Min($resultCount - 1, $selectedIndex + $visibleItemCount)
                                }
                            }
                            'Home' {
                                if ($resultCount -gt 0) {
                                    $selectedIndex = 0
                                }
                            }
                            'End' {
                                if ($resultCount -gt 0) {
                                    $selectedIndex = $resultCount - 1
                                }
                            }
                            'Enter' {
                                if ($resultCount -gt 0) {
                                    return $Items[$filteredIndexes[$selectedIndex]]
                                }
                            }
                            'Escape' {
                                return $null
                            }
                            'Backspace' {
                                if ($Searchable -and $searchText.Length -gt 0) {
                                    $searchText = $searchText.Substring(0, $searchText.Length - 1)
                                    $searchChanged = $true
                                }
                            }
                            'Delete' {
                                if ($Searchable -and $searchText.Length -gt 0) {
                                    $searchText = ''
                                    $searchChanged = $true
                                }
                            }
                            default {
                                if ($Searchable -and
                                    $key.KeyChar -ne [char]0 -and
                                    -not [char]::IsControl($key.KeyChar)) {
                                    $searchText += $key.KeyChar
                                    $searchChanged = $true
                                }
                            }
                        }

                        if ($searchChanged) {
                            if ([string]::IsNullOrEmpty($searchText)) {
                                $filteredIndexes = @($allItemIndexes)
                            }
                            else {
                                $filteredIndexes = @(
                                    foreach ($itemIndex in $allItemIndexes) {
                                        if ($displayLabels[$itemIndex].IndexOf(
                                                $searchText,
                                                [StringComparison]::OrdinalIgnoreCase
                                            ) -ge 0) {
                                            $itemIndex
                                        }
                                    }
                                )
                            }

                            $selectedIndex = 0
                            $firstVisibleIndex = 0
                        }
                    }
                }
                catch {
                    Write-Host "`nThe interactive menu is not available in this terminal. Falling back to numbered selection." -ForegroundColor Yellow
                }
                finally {
                    if ($menuStarted) {
                        try {
                            [Console]::BackgroundColor = $originalBackgroundColor
                            [Console]::ForegroundColor = $originalForegroundColor
                            [Console]::CursorVisible = $originalCursorVisible
                            [Console]::SetCursorPosition(0, $menuTop + $visibleItemCount)
                            Write-Host ''
                        }
                        catch {
                            # The console may have been resized or closed while the menu was active.
                        }
                    }
                }
            }

            $fallbackIndexes = @($allItemIndexes)
            if ($Searchable) {
                $fallbackSearch = Read-Host "`nSearch, or press Enter to show all items"
                if (-not [string]::IsNullOrEmpty($fallbackSearch)) {
                    $fallbackIndexes = @(
                        foreach ($itemIndex in $allItemIndexes) {
                            if ($displayLabels[$itemIndex].IndexOf(
                                    $fallbackSearch,
                                    [StringComparison]::OrdinalIgnoreCase
                                ) -ge 0) {
                                $itemIndex
                            }
                        }
                    )

                    if ($fallbackIndexes.Count -eq 0) {
                        Write-Host 'No matching item. Showing all items.' -ForegroundColor Yellow
                        $fallbackIndexes = @($allItemIndexes)
                    }
                }
            }

            Write-Host "`n$Title" -ForegroundColor Yellow
            for ($choiceIndex = 0; $choiceIndex -lt $fallbackIndexes.Count; $choiceIndex++) {
                $itemIndex = $fallbackIndexes[$choiceIndex]
                Write-Host "[$choiceIndex] $($displayLabels[$itemIndex])"
            }

            while ($true) {
                $choice = Read-Host 'Enter an index, or press Enter to cancel'
                if ([string]::IsNullOrWhiteSpace($choice)) {
                    return $null
                }

                $selectedChoiceIndex = 0
                if ([int]::TryParse($choice, [ref]$selectedChoiceIndex) -and
                    $selectedChoiceIndex -ge 0 -and
                    $selectedChoiceIndex -lt $fallbackIndexes.Count) {
                    return $Items[$fallbackIndexes[$selectedChoiceIndex]]
                }

                Write-Host 'Invalid selection. Try again.' -ForegroundColor Yellow
            }
        }

        # test if az connected with az ad signed-in-user show
        $result = az ad signed-in-user show --output json 2>&1
    
        if ($LASTEXITCODE -ne 0) {
            Write-Host -ForegroundColor Cyan 'You are not signed in to Azure. Please sign in using az login.'
            az login
        }
    
        $bastions = @(az network bastion list --output json | ConvertFrom-Json)

        if ($bastions.Count -eq 0) {
            Write-Host -ForegroundColor Yellow 'No Bastion host was found in the current subscription.'
            return
        }

        # If several bastions exist, ask the user to choose
        if ($bastions.Count -gt 1) {
            $selectedBastion = Select-ConsoleItem `
                -Items $bastions `
                -Title 'Select a Bastion host' `
                -DisplayItem { param($Bastion) "$($Bastion.name)  [$($Bastion.resourceGroup)]" }

            if ($null -eq $selectedBastion) {
                Write-Host -ForegroundColor Yellow 'Selection cancelled.'
                return
            }

            Write-Host -ForegroundColor Green "You have selected $($selectedBastion.name) as Bastion."
        }
        else {
            Write-Host -ForegroundColor Green "You have only one Bastion available: $($bastions[0].name) so we will use it."
            $selectedBastion = $bastions[0]
        }

        $vms = @(az vm list --output json | ConvertFrom-Json)

        if ($vms.Count -eq 0) {
            Write-Host -ForegroundColor Yellow 'No virtual machine was found in the current subscription.'
            return
        }

        $selectedVM = Select-ConsoleItem `
            -Items $vms `
            -Title 'Select a virtual machine' `
            -DisplayItem { param($VM) "$($VM.name)  [$($VM.resourceGroup)]" } `
            -Searchable

        if ($null -eq $selectedVM) {
            Write-Host -ForegroundColor Yellow 'Selection cancelled.'
            return
        }

        Write-Host -ForegroundColor Green "You have selected $($selectedVM.name) as VM."

        Write-Host "`nConnecting to $($selectedVM.name) using $($selectedBastion.name) as Bastion..."

        # Check for existing RDP file less than 1 hour old
        $tempFolder = [System.IO.Path]::GetTempPath()
        $rdpPattern = "*$($selectedVM.name)*.rdp"
        $existingRdpFile = Get-ChildItem -Path $tempFolder -Filter $rdpPattern | Where-Object { 
            $_.CreationTime -gt (Get-Date).AddHours(-1) 
        } | Sort-Object CreationTime -Descending | Select-Object -First 1

        if ($existingRdpFile) {
            Write-Host -ForegroundColor Green "Found recent RDP file: $($existingRdpFile.Name) (created at $($existingRdpFile.CreationTime))"
            Write-Host -ForegroundColor Green 'Launching existing RDP file instead of downloading new one...'
            Start-Process -FilePath $existingRdpFile.FullName
        }
        else {
            Write-Host -ForegroundColor Yellow 'No recent RDP file found, downloading new one...'
            az network bastion rdp `
                --name $selectedBastion.name `
                --resource-group $selectedBastion.resourceGroup `
                --target-resource-id $selectedVM.id
        }
    }
    else {
        Add-Type -AssemblyName PresentationFramework
        Add-Type -AssemblyName PresentationCore

        [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AzBastionConnect"
        Width="760"
        Height="640"
        MinWidth="640"
        MinHeight="520"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanResize"
        SizeToContent="Height"
        FontFamily="Segoe UI"
        TextOptions.TextFormattingMode="Display"
        UseLayoutRounding="True">

    <Window.Resources>
        <SolidColorBrush x:Key="PrimaryBrush" Color="#0078D4"/>
        <SolidColorBrush x:Key="SecondaryBrush" Color="#106EBE"/>
        <SolidColorBrush x:Key="SuccessBrush" Color="#107C10"/>
        <SolidColorBrush x:Key="DangerBrush" Color="#C42B1C"/>
        <SolidColorBrush x:Key="BackgroundBrush" Color="#F5F7FA"/>
        <SolidColorBrush x:Key="SurfaceBrush" Color="#FFFFFF"/>
        <SolidColorBrush x:Key="SubtleSurfaceBrush" Color="#F7F9FC"/>
        <SolidColorBrush x:Key="BorderBrush" Color="#DADDE2"/>
        <SolidColorBrush x:Key="TextBrush" Color="#242424"/>
        <SolidColorBrush x:Key="TextSecondaryBrush" Color="#5F6368"/>
        <SolidColorBrush x:Key="DisabledBrush" Color="#EFF1F3"/>
        <SolidColorBrush x:Key="DisabledTextBrush" Color="#8A8886"/>

        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Background" Value="{StaticResource PrimaryBrush}"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderBrush" Value="{StaticResource PrimaryBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="13,0"/>
            <Setter Property="Height" Value="34"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="ButtonBorder"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="5"
                                SnapsToDevicePixels="True">
                            <ContentPresenter HorizontalAlignment="Center"
                                              VerticalAlignment="Center"
                                              Margin="{TemplateBinding Padding}"
                                              RecognizesAccessKey="True"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.86"/>
                            </Trigger>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="ButtonBorder" Property="BorderBrush" Value="{StaticResource TextBrush}"/>
                                <Setter TargetName="ButtonBorder" Property="BorderThickness" Value="2"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="ButtonBorder" Property="Background" Value="{StaticResource DisabledBrush}"/>
                                <Setter TargetName="ButtonBorder" Property="BorderBrush" Value="{StaticResource DisabledBrush}"/>
                                <Setter Property="Foreground" Value="{StaticResource DisabledTextBrush}"/>
                                <Setter Property="Cursor" Value="Arrow"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{StaticResource SecondaryBrush}"/>
                    <Setter Property="BorderBrush" Value="{StaticResource SecondaryBrush}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="SuccessButton" TargetType="Button" BasedOn="{StaticResource ModernButton}"/>

        <Style x:Key="SecondaryButton" TargetType="Button" BasedOn="{StaticResource ModernButton}">
            <Setter Property="Background" Value="{StaticResource SurfaceBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource TextSecondaryBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{StaticResource SubtleSurfaceBrush}"/>
                    <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
                    <Setter Property="BorderBrush" Value="#B8BDC5"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource ModernButton}">
            <Setter Property="Background" Value="{StaticResource SurfaceBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource DangerBrush}"/>
            <Setter Property="BorderBrush" Value="#E6A7A1"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#FDEBEC"/>
                    <Setter Property="BorderBrush" Value="{StaticResource DangerBrush}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="ModernComboBoxItem" TargetType="ComboBoxItem">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBoxItem">
                        <Border x:Name="ItemBorder"
                                Background="{TemplateBinding Background}"
                                CornerRadius="4"
                                Padding="10,6"
                                SnapsToDevicePixels="True">
                            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                                              VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter TargetName="ItemBorder" Property="Background" Value="#F0F6FB"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="ItemBorder" Property="Background" Value="#E1F0FA"/>
                                <Setter Property="Foreground" Value="{StaticResource PrimaryBrush}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="ModernComboBox" TargetType="ComboBox">
            <Setter Property="Height" Value="34"/>
            <Setter Property="Padding" Value="11,0,4,0"/>
            <Setter Property="Background" Value="{StaticResource SurfaceBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="MaxDropDownHeight" Value="240"/>
            <Setter Property="ItemContainerStyle" Value="{StaticResource ModernComboBoxItem}"/>
            <Setter Property="ScrollViewer.CanContentScroll" Value="True"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <Border x:Name="ComboBorder"
                                    Background="{TemplateBinding Background}"
                                    BorderBrush="{TemplateBinding BorderBrush}"
                                    BorderThickness="{TemplateBinding BorderThickness}"
                                    CornerRadius="5"
                                    SnapsToDevicePixels="True">
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="34"/>
                                    </Grid.ColumnDefinitions>

                                    <ToggleButton x:Name="DropDownToggle"
                                                  Grid.ColumnSpan="2"
                                                  Background="Transparent"
                                                  BorderThickness="0"
                                                  ClickMode="Press"
                                                  Focusable="False"
                                                  IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                                        <ToggleButton.Template>
                                            <ControlTemplate TargetType="ToggleButton">
                                                <Border Background="Transparent"/>
                                            </ControlTemplate>
                                        </ToggleButton.Template>
                                    </ToggleButton>

                                    <ContentPresenter x:Name="ContentSite"
                                                      Grid.Column="0"
                                                      Margin="{TemplateBinding Padding}"
                                                      HorizontalAlignment="Left"
                                                      VerticalAlignment="Center"
                                                      Content="{TemplateBinding SelectionBoxItem}"
                                                      ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                                      ContentTemplateSelector="{TemplateBinding ItemTemplateSelector}"
                                                      IsHitTestVisible="False"/>

                                    <TextBox x:Name="PART_EditableTextBox"
                                             Grid.Column="0"
                                             Margin="{TemplateBinding Padding}"
                                             Padding="0"
                                             Style="{x:Null}"
                                             Background="Transparent"
                                             BorderThickness="0"
                                             Foreground="{TemplateBinding Foreground}"
                                             FontSize="{TemplateBinding FontSize}"
                                             VerticalContentAlignment="Center"
                                             IsReadOnly="{TemplateBinding IsReadOnly}"
                                             Visibility="Hidden"/>

                                    <Path x:Name="DropDownArrow"
                                          Grid.Column="1"
                                          Width="10"
                                          Height="6"
                                          Data="M 1,1 L 5,5 L 9,1"
                                          Stroke="{StaticResource TextSecondaryBrush}"
                                          StrokeThickness="1.5"
                                          StrokeStartLineCap="Round"
                                          StrokeEndLineCap="Round"
                                          StrokeLineJoin="Round"
                                          HorizontalAlignment="Center"
                                          VerticalAlignment="Center"
                                          RenderTransformOrigin="0.5,0.5"
                                          IsHitTestVisible="False">
                                        <Path.RenderTransform>
                                            <RotateTransform Angle="0"/>
                                        </Path.RenderTransform>
                                    </Path>
                                </Grid>
                            </Border>

                            <Popup x:Name="PART_Popup"
                                   Placement="Bottom"
                                   AllowsTransparency="True"
                                   Focusable="False"
                                   IsOpen="{TemplateBinding IsDropDownOpen}"
                                   PopupAnimation="Fade">
                                <Grid x:Name="DropDown"
                                      MinWidth="{TemplateBinding ActualWidth}"
                                      MaxHeight="{TemplateBinding MaxDropDownHeight}"
                                      Margin="0,4,0,8"
                                      SnapsToDevicePixels="True">
                                    <Border Background="{StaticResource SurfaceBrush}"
                                            BorderBrush="{StaticResource BorderBrush}"
                                            BorderThickness="1"
                                            CornerRadius="6"
                                            Padding="4">
                                        <Border.Effect>
                                            <DropShadowEffect BlurRadius="12"
                                                              ShadowDepth="3"
                                                              Opacity="0.16"
                                                              Color="#25364A"/>
                                        </Border.Effect>
                                        <ScrollViewer VerticalScrollBarVisibility="Auto"
                                                      HorizontalScrollBarVisibility="Disabled"
                                                      CanContentScroll="True">
                                            <ItemsPresenter/>
                                        </ScrollViewer>
                                    </Border>
                                </Grid>
                            </Popup>
                        </Grid>

                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ComboBorder" Property="BorderBrush" Value="#AAB2BC"/>
                            </Trigger>
                            <Trigger Property="IsKeyboardFocusWithin" Value="True">
                                <Setter TargetName="ComboBorder" Property="BorderBrush" Value="{StaticResource PrimaryBrush}"/>
                                <Setter TargetName="ComboBorder" Property="BorderThickness" Value="2"/>
                            </Trigger>
                            <Trigger Property="IsDropDownOpen" Value="True">
                                <Setter TargetName="ComboBorder" Property="BorderBrush" Value="{StaticResource PrimaryBrush}"/>
                                <Setter TargetName="ComboBorder" Property="BorderThickness" Value="2"/>
                                <Setter TargetName="DropDownArrow" Property="RenderTransform">
                                    <Setter.Value>
                                        <RotateTransform Angle="180"/>
                                    </Setter.Value>
                                </Setter>
                            </Trigger>
                            <Trigger Property="IsEditable" Value="True">
                                <Setter TargetName="ContentSite" Property="Visibility" Value="Hidden"/>
                                <Setter TargetName="PART_EditableTextBox" Property="Visibility" Value="Visible"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="ComboBorder" Property="Background" Value="{StaticResource DisabledBrush}"/>
                                <Setter TargetName="ComboBorder" Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
                                <Setter TargetName="DropDownArrow" Property="Stroke" Value="{StaticResource DisabledTextBrush}"/>
                                <Setter Property="Foreground" Value="{StaticResource DisabledTextBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="FieldLabel" TargetType="TextBlock">
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
            <Setter Property="Margin" Value="0,0,0,5"/>
        </Style>

        <Style x:Key="ModernTextBox" TargetType="TextBox">
            <Setter Property="Background" Value="#FBFCFE"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10"/>
            <Setter Property="FontFamily" Value="Cascadia Mono, Consolas"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="Foreground" Value="{StaticResource TextSecondaryBrush}"/>
        </Style>

        <Style x:Key="Card" TargetType="Border">
            <Setter Property="Background" Value="{StaticResource SurfaceBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="8"/>
            <Setter Property="Padding" Value="18"/>
            <Setter Property="Margin" Value="0,0,0,12"/>
        </Style>

        <Style x:Key="StepCircle" TargetType="Border">
            <Setter Property="Width" Value="26"/>
            <Setter Property="Height" Value="26"/>
            <Setter Property="CornerRadius" Value="13"/>
            <Setter Property="Background" Value="{StaticResource DisabledBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>

        <Style x:Key="LoadingSpinner" TargetType="Border">
            <Setter Property="Width" Value="14"/>
            <Setter Property="Height" Value="14"/>
            <Setter Property="BorderBrush" Value="{StaticResource PrimaryBrush}"/>
            <Setter Property="BorderThickness" Value="2"/>
            <Setter Property="CornerRadius" Value="7"/>
            <Setter Property="Margin" Value="0,0,8,0"/>
            <Setter Property="RenderTransform">
                <Setter.Value>
                    <RotateTransform/>
                </Setter.Value>
            </Setter>
            <Setter Property="RenderTransformOrigin" Value="0.5,0.5"/>
            <Style.Triggers>
                <Trigger Property="Visibility" Value="Visible">
                    <Trigger.EnterActions>
                        <BeginStoryboard>
                            <Storyboard RepeatBehavior="Forever">
                                <DoubleAnimation Storyboard.TargetProperty="RenderTransform.(RotateTransform.Angle)"
                                                 From="0"
                                                 To="360"
                                                 Duration="0:0:1"/>
                            </Storyboard>
                        </BeginStoryboard>
                    </Trigger.EnterActions>
                </Trigger>
            </Style.Triggers>
        </Style>
    </Window.Resources>

    <Grid Background="{StaticResource BackgroundBrush}">
        <ScrollViewer x:Name="mainScrollViewer"
                      VerticalScrollBarVisibility="Auto"
                      HorizontalScrollBarVisibility="Disabled"
                      Padding="22">
            <StackPanel MaxWidth="716">

                <Grid Margin="4,0,4,18">
                    <StackPanel>
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="AzBastionConnect"
                                       FontSize="22"
                                       FontWeight="SemiBold"
                                       Foreground="{StaticResource TextBrush}"/>
                            <Border Background="#E8F2FB"
                                    CornerRadius="9"
                                    Padding="7,2"
                                    Margin="10,2,0,0"
                                    VerticalAlignment="Center">
                                <TextBlock Text="v$version"
                                           FontSize="10"
                                           FontWeight="SemiBold"
                                           Foreground="{StaticResource PrimaryBrush}"/>
                            </Border>
                            <TextBlock Margin="10,1,0,0"
                                       VerticalAlignment="Center">
                                <Hyperlink x:Name="linkClidsys"
                                           NavigateUri="https://clidsys.com"
                                           TextDecorations="None"
                                           Foreground="{StaticResource TextSecondaryBrush}">
                                    <TextBlock Text="by Clidsys" FontSize="11"/>
                                </Hyperlink>
                            </TextBlock>
                        </StackPanel>
                        <TextBlock Text="Connect securely to a VM through Azure Bastion"
                                   Margin="0,4,0,0"
                                   FontSize="13"
                                   Foreground="{StaticResource TextSecondaryBrush}"/>
                    </StackPanel>
                </Grid>

                <Border Style="{StaticResource Card}">
                    <StackPanel>

                        <Grid Margin="0,0,0,18">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>

                            <StackPanel Grid.Column="0" Orientation="Horizontal">
                                <Border x:Name="borderStepAccount"
                                        Style="{StaticResource StepCircle}"
                                        Background="{StaticResource PrimaryBrush}"
                                        BorderBrush="{StaticResource PrimaryBrush}">
                                    <TextBlock x:Name="txtStepAccountNumber"
                                               Text="1"
                                               FontSize="11"
                                               FontWeight="SemiBold"
                                               Foreground="White"
                                               HorizontalAlignment="Center"
                                               VerticalAlignment="Center"/>
                                </Border>
                                <TextBlock Text="Azure account"
                                           Margin="8,0,0,0"
                                           FontSize="12"
                                           FontWeight="SemiBold"
                                           Foreground="{StaticResource TextBrush}"
                                           VerticalAlignment="Center"/>
                            </StackPanel>

                            <Border x:Name="lineAccountTarget"
                                    Grid.Column="1"
                                    Height="1"
                                    Margin="14,0"
                                    Background="{StaticResource BorderBrush}"
                                    VerticalAlignment="Center"/>

                            <StackPanel Grid.Column="2" Orientation="Horizontal">
                                <Border x:Name="borderStepTarget" Style="{StaticResource StepCircle}">
                                    <TextBlock x:Name="txtStepTargetNumber"
                                               Text="2"
                                               FontSize="11"
                                               FontWeight="SemiBold"
                                               Foreground="{StaticResource DisabledTextBrush}"
                                               HorizontalAlignment="Center"
                                               VerticalAlignment="Center"/>
                                </Border>
                                <TextBlock Text="Virtual machine"
                                           Margin="8,0,0,0"
                                           FontSize="12"
                                           FontWeight="SemiBold"
                                           Foreground="{StaticResource TextSecondaryBrush}"
                                           VerticalAlignment="Center"/>
                            </StackPanel>

                            <Border x:Name="lineTargetConnect"
                                    Grid.Column="3"
                                    Height="1"
                                    Margin="14,0"
                                    Background="{StaticResource BorderBrush}"
                                    VerticalAlignment="Center"/>

                            <StackPanel Grid.Column="4" Orientation="Horizontal">
                                <Border x:Name="borderStepConnect" Style="{StaticResource StepCircle}">
                                    <TextBlock x:Name="txtStepConnectNumber"
                                               Text="3"
                                               FontSize="11"
                                               FontWeight="SemiBold"
                                               Foreground="{StaticResource DisabledTextBrush}"
                                               HorizontalAlignment="Center"
                                               VerticalAlignment="Center"/>
                                </Border>
                                <TextBlock Text="Connect"
                                           Margin="8,0,0,0"
                                           FontSize="12"
                                           FontWeight="SemiBold"
                                           Foreground="{StaticResource TextSecondaryBrush}"
                                           VerticalAlignment="Center"/>
                            </StackPanel>
                        </Grid>

                        <Border Height="1"
                                Background="{StaticResource BorderBrush}"
                                Margin="0,0,0,18"/>

                        <Border x:Name="borderConnectionStatus"
                                Background="{StaticResource SubtleSurfaceBrush}"
                                BorderBrush="{StaticResource BorderBrush}"
                                BorderThickness="1"
                                CornerRadius="6"
                                Padding="12"
                                Margin="0,0,0,20">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>

                                <Border x:Name="borderStatusIcon"
                                        Grid.Column="0"
                                        Background="#F0F3F7"
                                        BorderBrush="{StaticResource BorderBrush}"
                                        BorderThickness="1"
                                        CornerRadius="14"
                                        Width="28"
                                        Height="28"
                                        Margin="0,0,10,0">
                                    <TextBlock Text="○"
                                               FontFamily="Segoe UI Symbol"
                                               FontSize="15"
                                               Foreground="{StaticResource TextSecondaryBrush}"
                                               HorizontalAlignment="Center"
                                               VerticalAlignment="Center"/>
                                </Border>

                                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                                    <StackPanel Orientation="Horizontal">
                                        <Border x:Name="loadingSpinner"
                                                Style="{StaticResource LoadingSpinner}"
                                                Visibility="Collapsed"/>
                                        <TextBlock x:Name="txtConnectionStatus"
                                                   Text="Not connected to Azure"
                                                   FontSize="13"
                                                   FontWeight="SemiBold"
                                                   Foreground="{StaticResource TextBrush}"
                                                   VerticalAlignment="Center"/>
                                    </StackPanel>
                                    <TextBlock x:Name="txtConnectedUser"
                                               Text=""
                                               Margin="0,2,0,0"
                                               FontSize="11"
                                               Foreground="{StaticResource TextSecondaryBrush}"
                                               Visibility="Collapsed"/>
                                </StackPanel>

                                <Button x:Name="btnConnection"
                                        Grid.Column="2"
                                        Content="Login to Azure"
                                        Style="{StaticResource ModernButton}"
                                        MinWidth="124"/>
                            </Grid>
                        </Border>

                        <StackPanel x:Name="resourceSelectionPanel"
                                    Opacity="0.50"
                                    IsHitTestVisible="False">
                            <Grid Margin="0,0,0,14">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <StackPanel Grid.Column="0">
                                    <TextBlock Text="Choose a virtual machine"
                                               FontSize="16"
                                               FontWeight="SemiBold"
                                               Foreground="{StaticResource TextBrush}"/>
                                    <TextBlock x:Name="txtResourceHint"
                                               Text="Sign in to load subscriptions and Azure resources."
                                               Margin="0,3,0,0"
                                               FontSize="11"
                                               Foreground="{StaticResource TextSecondaryBrush}"/>
                                </StackPanel>
                                <StackPanel Grid.Column="1"
                                            Orientation="Horizontal"
                                            VerticalAlignment="Center">
                                    <Border x:Name="resourceLoadingSpinner"
                                            Style="{StaticResource LoadingSpinner}"
                                            Visibility="Collapsed"/>
                                    <TextBlock x:Name="txtResourceStatus"
                                               Text=""
                                               FontSize="11"
                                               Foreground="{StaticResource TextSecondaryBrush}"
                                               VerticalAlignment="Center"/>
                                </StackPanel>
                            </Grid>

                            <StackPanel Margin="0,0,0,10">
                                <TextBlock Text="Subscription" Style="{StaticResource FieldLabel}"/>
                                <ComboBox x:Name="cboSubscription"
                                          Style="{StaticResource ModernComboBox}"
                                          ToolTip="Sign in to load subscriptions"
                                          IsEnabled="False"/>
                            </StackPanel>

                            <StackPanel Margin="0,0,0,10">
                                <TextBlock Text="Bastion host" Style="{StaticResource FieldLabel}"/>
                                <ComboBox x:Name="cboBastion"
                                          Style="{StaticResource ModernComboBox}"
                                          ToolTip="Select a subscription first"
                                          IsEnabled="False"/>
                            </StackPanel>

                            <StackPanel>
                                <TextBlock Text="Virtual machine" Style="{StaticResource FieldLabel}"/>
                                <ComboBox x:Name="cboVM"
                                          Style="{StaticResource ModernComboBox}"
                                          ToolTip="Select a Bastion host first"
                                          IsEditable="False"
                                          IsTextSearchEnabled="False"
                                          IsEnabled="False"/>
                            </StackPanel>
                        </StackPanel>

                        <Grid Margin="0,16,0,0">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <Button x:Name="btnRemoveRDP"
                                    Grid.Column="0"
                                    Content="Delete temporary RDP files"
                                    Style="{StaticResource SecondaryButton}"
                                    HorizontalAlignment="Left"/>
                            <Button x:Name="btnConnect"
                                    Grid.Column="1"
                                    Content="Connect to VM"
                                    Style="{StaticResource SuccessButton}"
                                    IsEnabled="False"
                                    MinWidth="150"/>
                        </Grid>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource Card}" Padding="14,12">
                    <Expander x:Name="expLog" Header="Activity log" IsExpanded="False">
                        <Expander.HeaderTemplate>
                            <DataTemplate>
                                <TextBlock Text="{Binding}"
                                           FontSize="13"
                                           FontWeight="SemiBold"
                                           Foreground="{StaticResource TextBrush}"/>
                            </DataTemplate>
                        </Expander.HeaderTemplate>
                        <TextBox x:Name="txtLog"
                                 Style="{StaticResource ModernTextBox}"
                                 Height="120"
                                 IsReadOnly="True"
                                 TextWrapping="Wrap"
                                 VerticalScrollBarVisibility="Auto"
                                 Margin="0,12,0,0"/>
                    </Expander>
                </Border>

            </StackPanel>
        </ScrollViewer>
    </Grid>
</Window>
"@

        $reader = New-Object System.Xml.XmlNodeReader $xaml
        $window = [Windows.Markup.XamlReader]::Load($reader)
        
        # Try to set icon if it exists
        try {
            $iconPath = Join-Path $PSScriptRoot 'img\azure-bastion-logo.ico'
            if (Test-Path $iconPath) {
                $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]::new($iconPath))
            }
        }
        catch {
            # Silently continue if icon cannot be loaded
        }

        $btnConnection = $window.FindName('btnConnection')
        $txtConnectedUser = $window.FindName('txtConnectedUser')
        $txtConnectionStatus = $window.FindName('txtConnectionStatus')
        $borderStatusIcon = $window.FindName('borderStatusIcon')
        $loadingSpinner = $window.FindName('loadingSpinner')
        $cboSubscription = $window.FindName('cboSubscription')
        $cboBastion = $window.FindName('cboBastion')
        $cboVM = $window.FindName('cboVM')
        $btnConnect = $window.FindName('btnConnect')
        $btnRemoveRDP = $window.FindName('btnRemoveRDP')
        $txtLog = $window.FindName('txtLog')
        $resourceLoadingSpinner = $window.FindName('resourceLoadingSpinner')
        $txtResourceStatus = $window.FindName('txtResourceStatus')
        $txtResourceHint = $window.FindName('txtResourceHint')
        $resourceSelectionPanel = $window.FindName('resourceSelectionPanel')
        $borderStepAccount = $window.FindName('borderStepAccount')
        $txtStepAccountNumber = $window.FindName('txtStepAccountNumber')
        $lineAccountTarget = $window.FindName('lineAccountTarget')
        $borderStepTarget = $window.FindName('borderStepTarget')
        $txtStepTargetNumber = $window.FindName('txtStepTargetNumber')
        $lineTargetConnect = $window.FindName('lineTargetConnect')
        $borderStepConnect = $window.FindName('borderStepConnect')
        $txtStepConnectNumber = $window.FindName('txtStepConnectNumber')

        # Variable pour tracker l'état de connexion
        $script:isConnected = $false

        function Set-ProgressState {
            param(
                [ValidateSet('Disconnected', 'Connected', 'Ready')]
                [string]$State
            )

            $borderStepAccount.Background = '#0078D4'
            $borderStepAccount.BorderBrush = '#0078D4'
            $txtStepAccountNumber.Foreground = 'White'
            $lineAccountTarget.Background = '#DADDE2'
            $borderStepTarget.Background = '#EFF1F3'
            $borderStepTarget.BorderBrush = '#DADDE2'
            $txtStepTargetNumber.Foreground = '#8A8886'
            $lineTargetConnect.Background = '#DADDE2'
            $borderStepConnect.Background = '#EFF1F3'
            $borderStepConnect.BorderBrush = '#DADDE2'
            $txtStepConnectNumber.Foreground = '#8A8886'
            $resourceSelectionPanel.Opacity = 0.50
            $resourceSelectionPanel.IsHitTestVisible = $false

            if ($State -in @('Connected', 'Ready')) {
                $borderStepAccount.Background = '#107C10'
                $borderStepAccount.BorderBrush = '#107C10'
                $lineAccountTarget.Background = '#0078D4'
                $borderStepTarget.Background = '#0078D4'
                $borderStepTarget.BorderBrush = '#0078D4'
                $txtStepTargetNumber.Foreground = 'White'
                $resourceSelectionPanel.Opacity = 1
                $resourceSelectionPanel.IsHitTestVisible = $true
            }

            if ($State -eq 'Ready') {
                $borderStepTarget.Background = '#107C10'
                $borderStepTarget.BorderBrush = '#107C10'
                $lineTargetConnect.Background = '#0078D4'
                $borderStepConnect.Background = '#0078D4'
                $borderStepConnect.BorderBrush = '#0078D4'
                $txtStepConnectNumber.Foreground = 'White'
            }
        }

        $btnConnection.Add_Click({
                if (-not $script:isConnected) {
                    # Mode Login
                    $txtLog.Text = "Check Azure connection...`r`n" + $txtLog.Text
                    $txtConnectionStatus.Text = "Connecting..."
                    $borderStatusIcon.Background = "#FFF3CD"
                    $borderStatusIcon.BorderBrush = "#FFEAA7"
                    $borderStatusIcon.Child.Text = "..."
                    $loadingSpinner.Visibility = 'Visible'
                    $btnConnection.IsEnabled = $false
                    
                    # Use dispatcher to update UI and run Azure commands asynchronously
                    $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [System.Action]{
                        try {
                            $result = az ad signed-in-user show --output json 2>&1
                    
                            if ($LASTEXITCODE -ne 0) {
                                $txtLog.Text = "Connecting to Azure...`r`n" + $txtLog.Text
                                az login | Out-Null
                            }
                    
                            $subscriptions = az account list --output json | ConvertFrom-Json
                            
                            # Return to UI thread for updates
                            $window.Dispatcher.Invoke({
                                $loadingSpinner.Visibility = 'Collapsed'
                                $btnConnection.IsEnabled = $true
                                
                                $cboSubscription.ItemsSource = @(
                                    [PSCustomObject]@{ Id = $null; Name = $null; Display = 'Select a subscription' }
                                ) + @($subscriptions | ForEach-Object {
                                    [PSCustomObject]@{
                                        Id      = $_.id
                                        Name    = $_.name
                                        Display = '{0} ({1})' -f $_.name, $_.id
                                    }
                                })
                                $cboSubscription.DisplayMemberPath = 'Display'
                                $cboSubscription.SelectedValuePath = 'Id'
                                $cboSubscription.IsEnabled = $true
                                $cboSubscription.SelectedIndex = 0
                        
                                $txtLog.Text = "Successful connection to Azure.`r`n" + $txtLog.Text
                                $currentUser = (az ad signed-in-user show --output json | ConvertFrom-Json).userPrincipalName
                                
                                # Mettre à jour le statut de connexion
                                $txtConnectionStatus.Text = "Connected to Azure"
                                $txtConnectedUser.Text = $currentUser
                                $txtConnectedUser.Visibility = 'Visible'
                                $borderStatusIcon.Background = "#D1E7DD"
                                $borderStatusIcon.BorderBrush = "#BADBCC"
                                $borderStatusIcon.Child.Text = "✓"
                                $txtResourceHint.Text = 'Choose a subscription, a Bastion host, and a virtual machine.'
                                Set-ProgressState -State 'Connected'
                                
                                # Changer le bouton en mode déconnexion
                                $btnConnection.Content = 'Disconnect'
                                $btnConnection.Style = $window.FindResource('DangerButton')
                                $script:isConnected = $true
                                
                                # Adjust window size after connection
                                AdjustWindowSize
                            })
                        }
                        catch {
                            $window.Dispatcher.Invoke({
                                $loadingSpinner.Visibility = 'Collapsed'
                                $btnConnection.IsEnabled = $true
                                $txtConnectionStatus.Text = "Connection failed"
                                $borderStatusIcon.Background = "#F8D7DA"
                                $borderStatusIcon.BorderBrush = "#F5C6CB"
                                $borderStatusIcon.Child.Text = "×"
                                $txtResourceHint.Text = 'Sign in to load subscriptions and Azure resources.'
                                Set-ProgressState -State 'Disconnected'
                                $txtLog.Text = "Connection error: $_`r`n" + $txtLog.Text
                            })
                        }
                    })
                }
                else {
                    # Mode Disconnect
                    try {
                        $txtLog.Text = "Disconnecting from Azure...`r`n" + $txtLog.Text
                        
                        # Logout from Azure CLI
                        $null = az logout
                        
                        # Reset UI state
                        $txtConnectionStatus.Text = "Not connected to Azure"
                        $txtConnectedUser.Text = ""
                        $txtConnectedUser.Visibility = 'Collapsed'
                        $borderStatusIcon.Background = "#F0F3F7"
                        $borderStatusIcon.BorderBrush = "#DADDE2"
                        $borderStatusIcon.Child.Text = "○"
                        $txtResourceHint.Text = 'Sign in to load subscriptions and Azure resources.'
                        Set-ProgressState -State 'Disconnected'
                        
                        # Clear and disable all combo boxes
                        $cboSubscription.ItemsSource = $null
                        $cboSubscription.IsEnabled = $false
                        $cboBastion.ItemsSource = $null
                        $cboBastion.IsEnabled = $false
                        $cboVM.ItemsSource = $null
                        $cboVM.Text = ''
                        $cboVM.IsEditable = $false
                        $cboVM.IsEnabled = $false
                        $btnConnect.IsEnabled = $false
                        
                        # Clear script variables
                        $script:bastions = $null
                        $script:vms = $null
                        $script:allVMDisplayItems = $null
                        
                        # Changer le bouton en mode connexion
                        $btnConnection.Content = 'Login to Azure'
                        $btnConnection.Style = $window.FindResource('ModernButton')
                        $script:isConnected = $false
                        
                        $txtLog.Text = "Successfully disconnected from Azure. Please login again to continue.`r`n" + $txtLog.Text
                        
                        # Adjust window size after disconnection
                        AdjustWindowSize
                    }
                    catch {
                        $txtLog.Text = "Error during disconnect: $_`r`n" + $txtLog.Text
                    }
                }
            })



        $cboSubscription.Add_SelectionChanged({
                if ($null -ne $cboSubscription.SelectedItem -and $null -ne $cboSubscription.SelectedItem.Id) {
                    LoadBastions
                }
            })

        $cboBastion.Add_SelectionChanged({
                if ($cboBastion.SelectedItem -and $null -ne $cboBastion.SelectedItem.Name) {
                    LoadVMs
                }
            })

        $script:vmSelecting = $false

        $cboVM.Add_SelectionChanged({
                if ($null -ne $cboVM.SelectedItem) {
                    $script:vmSelecting = $true
                }
                $btnConnect.IsEnabled = $null -ne $cboVM.SelectedItem
                if ($btnConnect.IsEnabled) {
                    $txtResourceHint.Text = 'Virtual machine selected. You can connect now.'
                    Set-ProgressState -State 'Ready'
                }
                elseif ($script:isConnected) {
                    Set-ProgressState -State 'Connected'
                }
            })

        $cboVM.AddHandler(
            [System.Windows.Controls.Primitives.TextBoxBase]::TextChangedEvent,
            [System.Windows.Controls.TextChangedEventHandler]{
                if ($script:vmSelecting) {
                    $script:vmSelecting = $false
                    return
                }
                $filter = $cboVM.Text
                if ([string]::IsNullOrEmpty($filter)) {
                    $cboVM.ItemsSource = $script:allVMDisplayItems
                }
                else {
                    $cboVM.ItemsSource = $script:allVMDisplayItems | Where-Object { $_.Name -like "*$filter*" }
                }
                $cboVM.IsDropDownOpen = $true
                $btnConnect.IsEnabled = $null -ne $cboVM.SelectedItem
                if ($btnConnect.IsEnabled) {
                    $txtResourceHint.Text = 'Virtual machine selected. You can connect now.'
                    Set-ProgressState -State 'Ready'
                }
                elseif ($script:isConnected) {
                    Set-ProgressState -State 'Connected'
                }
            }
        )

        $btnConnect.Add_Click({
                $selectedBastion = $script:bastions | Where-Object { 
                    $_.name -eq $cboBastion.SelectedItem.Name 
                }
                $selectedVM = $script:vms | Where-Object { 
                    $_.name -eq $cboVM.SelectedItem.Name 
                }

                $txtLog.Text = "Connection to $($selectedVM.name) via $($selectedBastion.name)...`r`n" + $txtLog.Text

                # Check for existing RDP file less than 1 hour old
                try {
                    $tempFolder = [System.IO.Path]::GetTempPath()
                    $rdpPattern = "*$($selectedVM.name)*.rdp"
                    $existingRdpFile = Get-ChildItem -Path $tempFolder -Filter $rdpPattern | Where-Object { 
                        $_.CreationTime -gt (Get-Date).AddHours(-1) 
                    } | Sort-Object CreationTime -Descending | Select-Object -First 1

                    if ($existingRdpFile) {
                        $txtLog.Text = "Found recent RDP file: $($existingRdpFile.Name) (created at $($existingRdpFile.CreationTime))`r`n" + $txtLog.Text
                        $txtLog.Text = "Launching existing RDP file instead of downloading new one...`r`n" + $txtLog.Text
                        
                        # Launch RDP file asynchronously to keep GUI open
                        $job = Start-Job -ScriptBlock {
                            param($rdpPath)
                            Start-Process -FilePath $rdpPath -Wait
                        } -ArgumentList $existingRdpFile.FullName
                        
                        $txtLog.Text = "RDP connection launched successfully. GUI remains available for new connections.`r`n" + $txtLog.Text
                    }
                    else {
                        $txtLog.Text = "No recent RDP file found, downloading new one...`r`n" + $txtLog.Text
                        
                        # Launch Azure CLI command asynchronously to keep GUI open
                        $job = Start-Job -ScriptBlock {
                            param($bastionName, $resourceGroup, $vmId)
                            az network bastion rdp --name $bastionName --resource-group $resourceGroup --target-resource-id $vmId
                        } -ArgumentList $selectedBastion.name, $selectedBastion.resourceGroup, $selectedVM.id
                        
                        $txtLog.Text = "RDP download started. GUI remains available for new connections.`r`n" + $txtLog.Text
                    }
                }
                catch {
                    $txtLog.Text = "Error checking for existing RDP file: $_`r`n" + $txtLog.Text
                    $txtLog.Text = "Downloading new RDP file...`r`n" + $txtLog.Text
                    
                    # Launch Azure CLI command asynchronously to keep GUI open
                    $job = Start-Job -ScriptBlock {
                        param($bastionName, $resourceGroup, $vmId)
                        az network bastion rdp --name $bastionName --resource-group $resourceGroup --target-resource-id $vmId
                    } -ArgumentList $selectedBastion.name, $selectedBastion.resourceGroup, $selectedVM.id
                    
                    $txtLog.Text = "RDP download started. GUI remains available for new connections.`r`n" + $txtLog.Text
                }
            })
            
        $btnRemoveRDP.Add_Click({
                try {
                    $tempFolder = [System.IO.Path]::GetTempPath()
                    $rdpFiles = Get-ChildItem -Path $tempFolder -Filter '*.rdp' | Where-Object { $_.CreationTime -gt (Get-Date).AddHours(-5) }
                    
                    if ($rdpFiles.Count -gt 0) {
                        $confirmation = [System.Windows.MessageBox]::Show(
                            "Delete $($rdpFiles.Count) temporary RDP file(s) created in the last 5 hours?",
                            'Delete temporary RDP files',
                            [System.Windows.MessageBoxButton]::YesNo,
                            [System.Windows.MessageBoxImage]::Warning
                        )
                        if ($confirmation -ne [System.Windows.MessageBoxResult]::Yes) {
                            return
                        }

                        foreach ($file in $rdpFiles) {
                            Remove-Item -Path $file.FullName -Force
                            $txtLog.Text = "Removed RDP file: $($file.Name)`r`n" + $txtLog.Text
                        }
                        $txtLog.Text = "Successfully removed recent RDP files from temp folder.`r`n" + $txtLog.Text
                    }
                    else {
                        $txtLog.Text = "No recent RDP files found in temp folder.`r`n" + $txtLog.Text
                    }
                }
                catch {
                    $txtLog.Text = "Error removing RDP files: $_`r`n" + $txtLog.Text
                }
            })

        function LoadBastions {
            # Reset Bastion/VM combos before reloading for the newly selected subscription
            $cboBastion.ItemsSource = $null
            $cboBastion.IsEnabled = $false
            $cboVM.ItemsSource = $null
            $cboVM.Text = ''
            $cboVM.IsEditable = $false
            $cboVM.IsEnabled = $false
            $btnConnect.IsEnabled = $false
            $script:bastions = $null
            $script:vms = $null
            $script:allVMDisplayItems = $null
            Set-ProgressState -State 'Connected'

            # Show loading state before launching the blocking az call
            $cboSubscription.IsEnabled = $false
            $resourceLoadingSpinner.Visibility = 'Visible'
            $txtResourceStatus.Text = 'Loading Bastions...'
            $txtResourceHint.Text = 'Loading Bastion hosts for the selected subscription.'
            $script:selectedSubId = if ($null -ne $cboSubscription.SelectedItem) { $cboSubscription.SelectedItem.Id } else { $null }
            if ($script:selectedSubId) {
                $txtLog.Text = "Setting active subscription to $($script:selectedSubId)...`r`n" + $txtLog.Text
            }
            $txtLog.Text = "Loading Bastions...`r`n" + $txtLog.Text

            # Defer the az call so the UI has a chance to repaint with the loading state
            $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [System.Action] {
                try {
                    if ($script:selectedSubId) {
                        $null = az account set --subscription $script:selectedSubId 2>&1
                    }

                    $listArgs = if ($script:selectedSubId) { @('--subscription', $script:selectedSubId) } else { @() }
                    $script:bastions = az network bastion list @listArgs --output json | ConvertFrom-Json

                    $resourceLoadingSpinner.Visibility = 'Collapsed'
                    $txtResourceStatus.Text = ''
                    $cboSubscription.IsEnabled = $true

                    if ($script:bastions) {
                        $cboBastion.ItemsSource = @(
                            [PSCustomObject]@{ Name = $null; Display = 'Select a Bastion host' }
                        ) + @($script:bastions | ForEach-Object {
                                [PSCustomObject]@{
                                    Name    = $_.name
                                    Display = '{0} ({1})' -f $_.name, $_.resourceGroup
                                }
                            })
                        $cboBastion.DisplayMemberPath = 'Display'
                        $cboBastion.SelectedValuePath = 'Name'
                        $cboBastion.IsEnabled = $true
                        $cboBastion.SelectedIndex = 0

                        $txtResourceHint.Text = 'Choose a Bastion host to load virtual machines.'
                        $txtLog.Text = "Successfully loaded bastions.`r`n" + $txtLog.Text
                        AdjustWindowSize
                    }
                    else {
                        $txtResourceHint.Text = 'No Bastion host was found in this subscription.'
                        $txtLog.Text = "No Bastion found.`r`n" + $txtLog.Text
                    }
                }
                catch {
                    $resourceLoadingSpinner.Visibility = 'Collapsed'
                    $txtResourceStatus.Text = ''
                    $cboSubscription.IsEnabled = $true
                    $txtResourceHint.Text = 'Bastion hosts could not be loaded. Review the activity log.'
                    $txtLog.Text = "Error loading Bastions: $_`r`n" + $txtLog.Text
                }
            })
        }

        function LoadVMs {
            # Show loading state before launching the blocking az call
            $cboBastion.IsEnabled = $false
            $cboVM.IsEditable = $false
            $cboVM.IsEnabled = $false
            $btnConnect.IsEnabled = $false
            $resourceLoadingSpinner.Visibility = 'Visible'
            $txtResourceStatus.Text = 'Loading VMs...'
            $txtResourceHint.Text = 'Loading virtual machines for the selected subscription.'
            Set-ProgressState -State 'Connected'
            $txtLog.Text = "Loading VMs...`r`n" + $txtLog.Text

            $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [System.Action] {
                try {
                    $vmListArgs = if ($script:selectedSubId) { @('--subscription', $script:selectedSubId) } else { @() }
                    $script:vms = az vm list @vmListArgs --output json | ConvertFrom-Json

                    $resourceLoadingSpinner.Visibility = 'Collapsed'
                    $txtResourceStatus.Text = ''
                    $cboBastion.IsEnabled = $true

                    $script:allVMDisplayItems = @($script:vms | ForEach-Object {
                            [PSCustomObject]@{
                                Name    = $_.name
                                Display = '{0} ({1})' -f $_.name, $_.resourceGroup
                            }
                        })
                    $cboVM.Text = ''
                    $cboVM.ItemsSource = $script:allVMDisplayItems
                    $cboVM.DisplayMemberPath = 'Display'
                    $cboVM.SelectedValuePath = 'Name'
                    $cboVM.IsEditable = $true
                    $cboVM.IsEnabled = $true

                    if ($script:allVMDisplayItems.Count -gt 0) {
                        $cboVM.SelectedIndex = 0
                        $btnConnect.IsEnabled = $true
                        $txtResourceHint.Text = 'Virtual machine selected. You can connect now.'
                        Set-ProgressState -State 'Ready'
                    }
                    else {
                        $txtResourceHint.Text = 'No virtual machine was found in this subscription.'
                    }

                    $txtLog.Text = "Successfully loaded VMs.`r`n" + $txtLog.Text
                    AdjustWindowSize
                }
                catch {
                    $resourceLoadingSpinner.Visibility = 'Collapsed'
                    $txtResourceStatus.Text = ''
                    $cboBastion.IsEnabled = $true
                    $txtResourceHint.Text = 'Virtual machines could not be loaded. Review the activity log.'
                    $txtLog.Text = "Error loading VMs: $_`r`n" + $txtLog.Text
                }
            })
        }

        # Add event handler for Clidsys hyperlink
        $linkClidsys = $window.FindName('linkClidsys')
        if ($linkClidsys) {
            $linkClidsys.Add_RequestNavigate({
                    param($sender, $e)
                    Start-Process -FilePath $e.Uri.AbsoluteUri
                    $e.Handled = $true
                })
        }

        # Add event handler for Activity Log expander to resize window
        $expLog = $window.FindName('expLog')
        $mainScrollViewer = $window.FindName('mainScrollViewer')
        if ($expLog) {
            $script:collapsedWindowHeight = 0

            $expLog.Add_Expanded({
                    # ActualHeight reflects the auto-sized collapsed window, unlike Height.
                    $script:collapsedWindowHeight = $window.ActualHeight

                    $window.Dispatcher.BeginInvoke(
                        [System.Windows.Threading.DispatcherPriority]::Loaded,
                        [System.Action]{
                            $window.UpdateLayout()

                            $logExpansionHeight = $txtLog.Height + $txtLog.Margin.Top + 24
                            $workArea = [System.Windows.SystemParameters]::WorkArea
                            $maximumWindowHeight = [Math]::Max(
                                $window.MinHeight,
                                [Math]::Floor($workArea.Height - 16)
                            )
                            $targetHeight = [Math]::Min(
                                $script:collapsedWindowHeight + $logExpansionHeight,
                                $maximumWindowHeight
                            )

                            $window.SizeToContent = 'Manual'
                            $window.Height = $targetHeight

                            # Keep the resized window fully inside the current work area.
                            if (($window.Top + $window.Height) -gt $workArea.Bottom) {
                                $window.Top = [Math]::Max(
                                    $workArea.Top,
                                    $workArea.Bottom - $window.Height
                                )
                            }

                            $window.UpdateLayout()

                            # On smaller screens, reveal the log instead of leaving it clipped.
                            if ($mainScrollViewer) {
                                $txtLog.BringIntoView()
                            }
                        }
                    )
                })

            $expLog.Add_Collapsed({
                    $window.SizeToContent = 'Height'
                    $window.InvalidateMeasure()

                    if ($mainScrollViewer) {
                        $mainScrollViewer.ScrollToTop()
                    }
                })
        }
        
        # Add handler to adjust window size when connection status changes
        function AdjustWindowSize {
            # Force the window to recalculate its size
            $window.InvalidateMeasure()
            $window.UpdateLayout()
            
            # If the log is not expanded, allow automatic sizing
            if (-not $expLog.IsExpanded) {
                $window.SizeToContent = 'Height'
            }
        }

        $null = $window.ShowDialog()
    }
}
