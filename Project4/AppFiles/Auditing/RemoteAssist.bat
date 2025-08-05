set /p pcname=[Please input the computer name you would like to control.]
echo %username%, %pcname%, %time%, %date% >>"C:\Users\rchenry\Documents\Projects\DemoApp\Auditing"
msra /offerra %pcname%