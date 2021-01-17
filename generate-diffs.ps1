param ($old_version_folder, $new_version_folder);

if ([string]::IsNullOrEmpty($old_version_folder)) {
    Write-Host "old_version_folder was not provided! Exiting...";
    exit;
}
if ([string]::IsNullOrEmpty($new_version_folder)) {
    Write-Host "new_version_folder was not provided! Exiting...";
    exit;
}

Write-Output "Installing tools...";
dotnet tool install --global ilspycmd --version 7.0.0.6291-preview2;
npm install -g diff2html-cli;

Write-Output "Started...";
$mappings = @{};
$mappings.Add('bannerlord.referenceassemblies.core.earlyaccess', 'Core');
$mappings.Add('bannerlord.referenceassemblies.native.earlyaccess', 'Native');
$mappings.Add('bannerlord.referenceassemblies.sandbox.earlyaccess', 'SandBox');
$mappings.Add('bannerlord.referenceassemblies.storymode.earlyaccess', 'StoryMode');
$mappings.Add('bannerlord.referenceassemblies.custombattle.earlyaccess', 'CustomBattle');

$excludes = @(
    '*AutoGenerated*',
    '*BattlEye*');

$old  = [IO.Path]::Combine($(Get-Location), "temp", "old" );
$new  = [IO.Path]::Combine($(Get-Location), "temp", "new" );
$diff = [IO.Path]::Combine($(Get-Location), "temp", "diff");
$html = [IO.Path]::Combine($(Get-Location), "temp", "html");
New-Item -ItemType directory -Path $diff -Force | Out-Null;
New-Item -ItemType directory -Path $html -Force | Out-Null;

$old_folders = Get-ChildItem -Path $old_version_folder | Sort-Object -desc;
$new_folders = Get-ChildItem -Path $new_version_folder | Sort-Object -desc;

foreach ($key in $mappings.Keys) {
    $mapping = $mappings[$key];
    Write-Output "Handling $mapping...";
    
    $old_path = [IO.Path]::Combine($old_version_folder, $key);
    $new_path = [IO.Path]::Combine($new_version_folder, $key);
    if (!(Test-Path "$old_path")) { continue; }
    if (!(Test-Path "$new_path")) { continue; }

    $contains = $false;
    foreach ($of in $old_folders) { if ([IO.Path]::GetFileName($of) -eq $key) { $contains = $true; } }
    foreach ($nf in $new_folders) { if ([IO.Path]::GetFileName($nf) -eq $key) { $contains = $true; } }
    if (!$contains) { continue; }

    $old_files = Get-ChildItem -Path $($old_path + '/*.dll') -Recurse -Exclude $excludes | Sort-Object -desc;
    $new_files = Get-ChildItem -Path $($new_path + '/*.dll') -Recurse -Exclude $excludes | Sort-Object -desc;


    # generate source code based on the Public API
    Write-Output "Generating Stable source code...";
    foreach ($file in $old_files) {
        $fileWE = [IO.Path]::GetFileNameWithoutExtension($file);
        $old_folder  = [IO.Path]::Combine($old, $mapping, $fileWE);
        New-Item -ItemType directory -Path $old_folder -Force | Out-Null;

        Write-Output "Generating for $fileWE...";
        ilspycmd "$($file.FullName)" --project --outputdir "$old_folder" | Out-Null;
    }
    Write-Output  "Generating Beta source code...";
    foreach ($file in $new_files) {
        $fileWE = [IO.Path]::GetFileNameWithoutExtension($file);
        $new_folder  = [IO.Path]::Combine($new, $mapping, $fileWE);
        New-Item -ItemType directory -Path $new_folder -Force | Out-Null;

        Write-Output "Generating for $fileWE...";
        ilspycmd "$($file.FullName)" --project --outputdir "$new_folder" | Out-Null;
    }


    # delete csproj files
    Write-Output  "Deleting csproj's..."
    foreach ($file in $old_files) {
        $fileWE = [IO.Path]::GetFileNameWithoutExtension($file);    
        $old_folder = [IO.Path]::Combine($old, $mapping, $fileWE);
        $new_folder = [IO.Path]::Combine($new, $mapping, $fileWE);
        Get-ChildItem -Path $($old_folder + '/*.csproj') -Recurse -ErrorAction SilentlyContinue | foreach { Remove-Item -Path $_.FullName };
        Get-ChildItem -Path $($new_folder + '/*.csproj') -Recurse -ErrorAction SilentlyContinue | foreach { Remove-Item -Path $_.FullName };
    }
    foreach ($file in $new_files) {
        $fileWE = [IO.Path]::GetFileNameWithoutExtension($file);
        $old_folder = [IO.Path]::Combine($old, $mapping, $fileWE);
        $new_folder = [IO.Path]::Combine($new, $mapping, $fileWE);
        Get-ChildItem -Path $($old_folder + '/*.csproj') -Recurse -ErrorAction SilentlyContinue | foreach { Remove-Item -Path $_.FullName };
        Get-ChildItem -Path $($new_folder + '/*.csproj') -Recurse -ErrorAction SilentlyContinue | foreach { Remove-Item -Path $_.FullName };
    }


    # generate the diff, md and html files
    Write-Output "Generating diff's...";
    foreach ($file in $old_files) {
        $fileWE = [IO.Path]::GetFileNameWithoutExtension($file);
        $old_folder = [IO.Path]::Combine($old, $mapping, $fileWE);
        $new_folder = [IO.Path]::Combine($new, $mapping, $fileWE);

        $diff_folder = $([IO.Path]::Combine($diff, $mapping));
        $diff_file = $([IO.Path]::Combine($diff_folder, $fileWE + '.diff'));
        New-Item -ItemType directory -Path $diff_folder -Force | Out-Null;

        $html_folder = $([IO.Path]::Combine($html, $mapping));
        $html_file = $([IO.Path]::Combine($html_folder, $fileWE + '.html'));
        New-Item -ItemType directory -Path $html_folder -Force | Out-Null;

        Write-Output "Generating diff for $fileWE...";
        git diff --no-index "$old_folder" "$new_folder" --output $diff_file;
        if (![string]::IsNullOrEmpty($(Get-Content $diff_file))) {
            Write-Output "Generating html for $diff_file...";
            diff2html -i file -- $diff_file -F $html_file;
        }
    }
    foreach ($file in $new_files) {
        $fileWE = [IO.Path]::GetFileNameWithoutExtension($file);
        $old_folder = [IO.Path]::Combine($old, $mapping, $fileWE);
        $new_folder = [IO.Path]::Combine($new, $mapping, $fileWE);

        $diff_folder = $([IO.Path]::Combine($diff, $mapping));
        $diff_file = $([IO.Path]::Combine($diff_folder, $fileWE + '.diff'));
        New-Item -ItemType directory -Path $diff_folder -Force | Out-Null;

        $html_folder = $([IO.Path]::Combine($html, $mapping));
        $html_file = $([IO.Path]::Combine($html_folder, $fileWE + '.html'));
        New-Item -ItemType directory -Path $html_folder -Force | Out-Null;

        Write-Output "Generating diff for $fileWE...";
        git diff --no-index "$old_folder" "$new_folder" --output $diff_file;
        if (![string]::IsNullOrEmpty($(Get-Content $diff_file))) {
            Write-Output "Generating html for $diff_file...";
            diff2html -i file -- $diff_file -F $html_file;
        }
    }
}