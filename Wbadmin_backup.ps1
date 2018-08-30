#Скрипт бекапа файлов на основе WBADMIN
#
#ДАТА:30 августа 2018 года
#
#-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# 
#Для успешного выполнения скрипта необходимо:
#Powersheel версии 4
#Установленная роль Windows server backup
#Доступность источника и хранилища бекапов
#Запуск скрипта от имени администратора(для установки роли Windows server backup)
#Powersheel ExecutionPolicy Unrestricted
#
#-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#Порядок выполнения скрипта(под катом): 
<# 

0- Задаем кодировку
1- Указываем переменные
2- Проверяем доступность источника бекапов, если нет - останавливаем скрипт
3- Проверяем доступность хранилища бекапов, если недоступно - пытаемся создать папку, если не получается - останавливаем скрипт
4- Проверяем версию Powersheel, минимально необходима 4 major, если версия ниже - останавливаем скрипт
5- Очищаем архивы старше 20 дней с логированием в отчет
6- Проверяем наличие Windows server backup, если не установлен - пробуем установить, если установлен - выполняем архивацию, если есть ошибки, будет отправлено письмо админу с отчетом

#>

#0 Задаем кодировку

ipconfig |Out-Null
[Console]:: outputEncoding = [System.Text.Encoding]::GetEncoding('cp866')

#1 Указываем пользовательские переменные:

#-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#задаем путь к источнику бекапов
$source = ""
#указываем путь к хранилищу бекапов
$destination = ''
#указываем список лиц для оповещения
[string[]]$recipients = ""# example - "test1@example.ru", "test2@example.ru", "test3@example.ru"
#указываем логин для отправки почты
$SmtpLogin = ""
#указываем пароль для отправки почты
$SmtpPassword = ""

#указываем служебные переменные:

#получаем текущую дату
$datetime = get-date
#имя папки будет в формате dd.mm.yyyy
$foldername = $datetime.toshortdatestring()
#создаем переменную LOG файла
$backuplog = "$destination\log\$foldername"+('.log')

#-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

#2 Проверяем доступность источника бекапов

$SourIsReach = {

try

{
    Get-ChildItem $source -ErrorAction Stop | Out-Null
    Write-Host "Source path $source is reachable" -ForegroundColor Green
}

catch

{
    Write-Host "Source path is unreachable!" -ForegroundColor Red
    Write-Output $Error[0].Exception.Message 
    Write-Host "Script terminated with error." -ForegroundColor Yellow
    Break
}

}

#3 Проверяем доступность хранилища бекапов

$DestIsReach = {

try

{
    #проверяем доступность хранилища бекапов, создаем папку для логов
    Get-ChildItem $destination -ErrorAction Stop | Out-Null
    Write-Host "Destination path $destination is reachable" -ForegroundColor Green
    #создадим папку для логов
    new-item $destination -name log -type directory -force | Out-Null
}
 
catch

{

Write-Host "Destination path $destination is unreachable, trying to create folder" -ForegroundColor Red 

try

{
    #пытаемся создать папку хранилища бекапов и папку логов
    new-item (Split-Path $destination -Qualifier) -name (Split-Path $destination -leaf) -type directory -force -ErrorAction Stop |Out-Null
    Write-Host "Destination folder has been created" -ForegroundColor Green
    #создадим папку для логов
    new-item $destination -name log -type directory -force | Out-Null
}

catch

{
    Write-Host "Cannot create destination folder!" -ForegroundColor Red
    Write-Output $Error[0].Exception.Message
    Write-Host "Script terminated with error." -ForegroundColor Yellow
    Break
}
 
}

}

#4 Проверяем версию Powersheel, минимально необходима 4 major

$PoshVerCheck = {

if ($host.version | select major | where-object {($_.major -cge "4")})

{Write-Host "PowerShell version is applicable" -ForegroundColor Green}

Else 

{
    Write-Host "Need to update powershell version at least to major 4!" -ForegroundColor RED
    Write-Host "Script terminated with error." -ForegroundColor Yellow
    Break 
}

}

#5 Очищаем старые архивы

$RemOldArch = {

#отнимаем 10 дней от текущей даты 
$datetime = $datetime.AddDays(-10) 
#процесс удаления файлов c логированием в отчет 
ls -r $destination | 
Where-Object {$datetime -gt $_.LastWriteTime } | rm -recurse -Verbose 4>&1 |Out-File "$backuplog" -Append

}

#6 Выполняем архивацию

$WbNewArch = {

#Проверка установленной роли Windows Server Backup, если не установлена, пробуем установить
if  (Get-WindowsFeature | where-object {($_.Name -like "*backup*" -and $_.InstallState -match "Installed")})
{Write-Host "Windows-Server-Backup is installed" -ForegroundColor Green}

else

{Write-Host "Windows-Server-Backup is not installed, trying to install" -ForegroundColor Red

try

{Add-WindowsFeature Windows-Server-Backup}

catch

{
    Write-Host "Cannot install Windows-Server-Backup" -ForegroundColor Red
    Write-Output $Error[0].Exception.Message 
    Write-Host "Script terminated with error." -ForegroundColor Yellow
    Break
}

}

#создаем папку для нового архива
new-item $destination -name $foldername -type directory -force | Out-Null
#выполняем архивацию c логированием в отчет
Write-Host "Backup start"
wbadmin.exe start backup -backupTarget:$destination\$foldername -include:$source -vssFull -quiet | Out-File "$backuplog" -Append
#выполняем проверку на успешность выполнения бекапа, если неуспешно - отправляем письмо с логом
if (Get-Content -path $backuplog |where {($_ -match "error") -or ($_ -match "Exception") -or ($_ -match "Ошибка") -or ($_ -like "*не хватает свободного места*") -or ($_ -like "*Not enough storage*")}) 

{
    Write-Host "Backup finished unsuccessfully, look for log in $backuplog" -ForegroundColor RED
    Write-Host "Sending email to $recipients"
    #задаем логин\пароль для отправки почты
    $secpasswd = ConvertTo-SecureString $SmtpPassword -AsPlainText -Force
    $mycreds = New-Object System.Management.Automation.PSCredential ($SmtpLogin, $secpasswd)
    #задаем тему письма для отчета по почте
    $EmailSubj = (Get-WmiObject -Class Win32_ComputerSystem |Select-Object -ExpandProperty "name")+" WBADMIN backup error"
    #формируем короткий отчет по прошедшему бекапу
    $Body = Get-WBSummary | Select-Object LastSuccessfulBackupTime | ft -AutoSize| Out-String 
    Write-Output "$Body" 
    #указываем параметры отправки почты
    $EmailParam = @{
        SmtpServer = 'smtp.gmail.com'
        Port = 587
        UseSsl = $true
        Credential  = $mycreds
        From = $SmtpLogin
        To = $recipients
        Subject = $EmailSubj
        Body = $Body
        Attachments = $backuplog
}
    #отправляем почту
    Write-Host "Sending email to $recipients"
    Send-MailMessage @EmailParam -Encoding ([System.Text.Encoding]::UTF8)}

Else 

{Write-Host "Backup finished successfully, full log in $backuplog" -ForegroundColor Green}

}

#-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

#7 Выполняем скрипт

Write-Host "Cheking conditions:" -ForegroundColor Yellow

& $SourIsReach
& $DestIsReach
& $PoshVerCheck
& $RemOldArch
& $WbNewArch

Write-Host "Script finished." -ForegroundColor Yellow

#-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

#8 Очищаем буфер с переменными

Remove-Variable -Name *  -Force -ErrorAction SilentlyContinue
