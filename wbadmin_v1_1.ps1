#Скрипт бекапа файлов на основе WBADMIN
#
#ДАТА:11 октября 2018 года										 
 
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
5- Пробуем очистить архивы старше 10 дней, если не получается - записываем в лог и продолжаем скрипт
6- Проверяем наличие Windows server backup, если не установлен - пробуем установить(если не получается - останавливаем скрипт), если установлен - выполняем архивацию, если есть ошибки, или в логе не будет сообщения об успешно выполненном бекапе - будет выполнена попытка отправки письма админу с отчетом
*- Все ошибки, а также события успешности выполнения бекапа, будут записаны в лог файл, который создается в той-же директории, что и скрипт

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
#задаем путь к глобальному логу скрипта
$globallog = "$PSScriptRoot\WbadminBackupLog"+('.log')

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
    Write-Output ("FATAL ERROR - Source path is unreachable "+(Get-Date)) | Out-File "$globallog" -Append
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
    Write-Output ("WARNING - Destination folder has been not found and was created "+(Get-Date -Format T)) | Out-File "$globallog" -Append
}

catch

{
    Write-Host "Cannot create destination folder!" -ForegroundColor Red
    Write-Output $Error[0].Exception.Message
    Write-Host "Script terminated with error." -ForegroundColor Yellow
    Write-Output ("FATAL ERROR - Destination folder create check not passed "+(Get-Date)) | Out-File "$globallog" -Append
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
    Write-Output ("FATAL ERROR - PowerShell check not passed "+(Get-Date)) | Out-File "$globallog" -Append
    Break 
}

}

#5 Очищаем старые архивы

$RemOldArch = {

														   
$datetime = (Get-Date).AddDays(-10) 
#получаем список файлов в хранилище бекапов
					 
																										 

try

{
    $BackupList = ls -r $destination
    #делаем выборку по полученным файлам
    $BackupList | Where-Object {$datetime -gt $_.LastWriteTime} |
    #процесс удаления файлов c логированием в отчет
    rm -recurse -Verbose 4>&1 |Out-File "$globallog" -Append
}

catch

{
    Write-Host "Cannot remove old archives!" -ForegroundColor Red
    Write-Output $Error[0].Exception.Message
    Write-Output "WARNING - Removing old archives failed" | Out-File "$globallog" -Append}
}

#6 Выполняем архивацию

$WbNewArch = {

#Проверка установленной роли Windows Server Backup, если не установлена, пробуем установить
if  (Get-WindowsFeature | where-object {($_.Name -like "*backup*" -and $_.InstallState -match "Installed")})
{Write-Host "Windows-Server-Backup is installed" -ForegroundColor Green}

else

{Write-Host "Windows-Server-Backup is not installed, trying to install" -ForegroundColor Red

try

{
    Add-WindowsFeature Windows-Server-Backup
    Write-Output ("WARNING - Windows-Server-Backup has been not found and was installed "+(Get-Date -Format T)) | Out-File "$globallog" -Append
}

catch

{
    Write-Host "Cannot install Windows-Server-Backup" -ForegroundColor Red
    Write-Output $Error[0].Exception.Message 
    Write-Host "Script terminated with error." -ForegroundColor Yellow
    Write-Output ("FATAL ERROR - No Windows-Server-Backup installed feature has been found, cannot install feature "+(Get-Date)) | Out-File "$globallog" -Append
    Break
}

}

#создаем папку для нового архива
new-item $destination -name $foldername -type directory -force | Out-Null
#выполняем архивацию c логированием в отчет
Write-Host "Backup start"
wbadmin.exe start backup -backupTarget:$destination\$foldername -include:$source -vssFull -quiet | Out-File "$backuplog" -Append
#выполняем проверку на успешность выполнения бекапа, если неуспешно - отправляем письмо с логом
if (Get-Content -path $backuplog |where {(($_ -match "error") -or ($_ -match "Exception") -or ($_ -match "Ошибка") -or ($_ -like "*не хватает свободного места*") -or ($_ -like "*Not enough storage*")) -and ($_ -notmatch "The backup operation successfully completed")}) 

{

try

{
    Write-Host "Backup finished unsuccessfully, look for log in $backuplog" -ForegroundColor RED
    Write-Host "Sending email to $recipients"
    Write-Output ("ERROR - errors found in log, sending email to $recipients "+(Get-Date -Format T)) | Out-File "$globallog" -Append
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
    Send-MailMessage @EmailParam -Encoding ([System.Text.Encoding]::UTF8)

}

catch

{ 
    Write-Host "Cannot send email!" -ForegroundColor Red
    Write-Output $Error[0].Exception.Message
    Write-Output ("ERROR - Email not sent "+(Get-Date -Format T)) | Out-File "$globallog" -Append
}

}

Else 

{
    Write-Host "Backup finished successfully, full log in $backuplog" -ForegroundColor Green
    Write-Output ("SUCCESS - Backup finished successfully "+(Get-Date -Format T)) | Out-File "$globallog" -Append
}

}

#-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

#7 Выполняем скрипт

#если какой-то скрипт-блок не нужен, достаточно закомментировать его выполнение ниже и это не повлияет на другие скрипт-блоки

Write-Host "Cheking conditions:" -ForegroundColor Yellow
Write-Output ("Start "+(Get-Date -Format D)) | Out-File "$globallog" -Append

& $SourIsReach
& $DestIsReach
& $PoshVerCheck
& $RemOldArch
& $WbNewArch

Write-Host "Script finished." -ForegroundColor Yellow
Write-Output ("Finish "+(Get-Date -Format D)) | Out-File "$globallog" -Append

#-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

#8 Очищаем буфер с переменными

Remove-Variable -Name *  -Force -ErrorAction SilentlyContinue
