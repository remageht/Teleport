$dst = 'C:\dev\radiotrade\android\gradle.properties'
Add-Content $dst "`n# Скорость сборки"
Add-Content $dst "org.gradle.parallel=true"
Add-Content $dst "org.gradle.caching=true"
Get-Content $dst
