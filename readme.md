i18n-update
===========

Script to update localizations for Rails apps using i18n-tasks.

Will automatically find any unstaged additions, removals, or changed i18n keys from a base locale file (by defualt: `config/locales/en.yml`) and update your other locales to match.

Run it from inside your Rails app:
```
ruby ~/whatever_dir/i18n-update.rb
```

Alternatively, put it in your Rails app's `bin` dir and mark it as executable.
```
cp i18n-update/i18n-update.rb myproj/bin/i18n-update
chmod +x myproj/bin/i18n-update
```

Then you can run it to your heart's content using:
```
bin/i18n-update
```

## Options:
- `-b config/locales/somelocale.yml` specify a different **B**ase locale (default is en.yml)
- `-h` command **H**elp (show these flags) 
- `-s` **S**taged changes
- `-v` **V**erbose mode 
- `-y` automatically approve (**Y**es)
