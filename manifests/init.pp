class gitorious($gitorious_host, $ssh_fingerprint,
                $dbpassword, $cookie_secret, 
                $gitorious_admin_email, $server_admin_email,
                $locale = "en", $default_license = "Other/Proprietary License",
                $useActiveMQ = false) {
    include gitorious::activemessaging
    include gitorious::memcached
    include gitorious::packages
    include gitorious::webserver
    include gitorious::database
    include gitorious::install
    include gitorious::config
    include gitorious::post-install
    include gitorious::services

    # Things better done before install (not all of which are necessarily dependencies)
    Class['gitorious::activemessaging'] -> Class['gitorious::install']
    Class['gitorious::memcached'] -> Class['gitorious::install']
    Class['gitorious::packages'] -> Class[ 'gitorious::install']
    Class['gitorious::webserver'] -> Class['gitorious::install']
    Class['gitorious::database'] -> Class['gitorious::install']

    # Install, config, post-install, and only then get the services up
    Class['gitorious::install'] -> Class['gitorious::config'] -> Class['gitorious::post-install'] -> Class['gitorious::services']

    # Changes to config or post-install get all services restarted
    Class['gitorious::config'] ~> Class['gitorious::services']
    Class['gitorious::post-install'] ~> Class['gitorious::services']

    # Memcached
    class memcached {
        package { 'memcached': ensure => installed, }
        service { 'memcached':
            ensure  => running,
            enable  => true,
            require => Package['memcached'],
        }
    }

    # webserver
    class webserver {
        # Because rvm only gets install with puppet >= 2.6.7, I can't have apache dependencies before that
        if versioncmp($puppetversion, '2.6.7') >= 0 {
            #include apache # Installed through rvm's passenger
            include apache::enable-mod-rewrite
            include apache::enable-mod-deflate
            #include apache::passenger # Installed through rvm
        }
    }

    # Database
    class database {
        include mysql::server

        package { 'libmysqlclient-dev': ensure => installed, }

        if $mysql_exists == 'true' {
            mysql_database { "gitorious":
                ensure => present,
                notify => Exec['reset-rake-tasks'],
            }

            # This creates the user if not defined elsewhere
            mysql::rights{ "Gitorious access to database":
              ensure   => present,
              database => "gitorious",
              user     => "git",
              password => "$dbpassword",
            }
        }
    }

    # Gitorious sw and required files and directories
    class install {
        ### Initial setup from repository ###
        if versioncmp($puppetversion, '2.6.7') >= 0 {
            group { 'gitorious':
                ensure => present,
                system => true,
            }
            user { 'git':
                ensure     => present,
                gid        => 'gitorious',
                groups     => [ 'rvm', ],
                home       => '/var/www/gitorious',
                shell      => '/bin/bash',
                managehome => false,  # Let vcsrepo create it
                system     => true,
                require    => Group['gitorious'],
            }
        } else {
            group { 'gitorious':
                ensure => present,
            }
            user { 'git':
                ensure     => present,
                gid        => 'gitorious',
                groups     => [ 'rvm', ],
                home       => '/var/www/gitorious',
                shell      => '/bin/bash',
                managehome => false,  # Let vcsrepo create it
                require    => Group['gitorious'],
            }
        }
        vcsrepo { '/var/www/gitorious':
            ensure   => present,
            owner    => 'git',
            group    => 'gitorious',
            source   => 'git://gitorious.org/gitorious/mainline.git',
            revision => 'v2.2.1',
            provider => git,
            require  => User['git'],
        }

        ### Directories where git will place its files
        file { '/var/lib/git':
            ensure => directory,
            owner  => 'git',
            group  => 'gitorious',
            mode   => 775,
        }
        file { '/var/lib/git/repositories':
            ensure  => directory,
            owner   => 'git',
            group   => 'gitorious',
            mode    => 775,
            require => File['/var/lib/git'],
        }
        file { '/var/lib/git/tarballs':
            ensure  => directory,
            owner   => 'git',
            group   => 'gitorious',
            mode    => 775,
            require => File['/var/lib/git'],
        }
        file { '/var/lib/git/tarballs-work':
            ensure  => directory,
            owner   => 'git',
            group   => 'gitorious',
            mode    => 775,
            require => File['/var/lib/git'],
        }

        ### Now make Ruby EE default on rvm and install gems through it ###
        ### git-daemon ###
        file { '/etc/init.d/git-daemon':
            ensure  => '/var/www/gitorious/doc/templates/ubuntu/git-daemon',
            require => Vcsrepo['/var/www/gitorious'],
        }
        common::replace { 'git-daemon-ruby-home': 
            file        => '/var/www/gitorious/doc/templates/ubuntu/git-daemon',
            pattern     => '\$RUBY_HOME/bin/ruby',
            replacement => '/usr/local/rvm/bin/rvm --with-rubies ree-1.8.7-2012.02\@gitorious do',
            require     => Vcsrepo['/var/www/gitorious'],
        }
        common::replace { 'git-daemon-provides': 
            file        => '/var/www/gitorious/doc/templates/ubuntu/git-daemon',
            pattern     => 'Gitorious GIT',
            replacement => 'Gitorious-GIT',
            require     => Vcsrepo['/var/www/gitorious'],
        }

        ### git-poller ###
        file { '/etc/init.d/git-poller':
            ensure  => '/var/www/gitorious/doc/templates/ubuntu/git-poller',
            require => Vcsrepo['/var/www/gitorious'],
        }
        common::replace { 'git-poller-ruby-home': 
            file        => '/var/www/gitorious/doc/templates/ubuntu/git-poller',
            pattern     => '\$RUBY_HOME/bin/ruby',
            replacement => '/usr/local/rvm/bin/rvm --with-rubies ree-1.8.7-2012.02\@gitorious do',
            require     => Vcsrepo['/var/www/gitorious'],
        }
        common::replace { 'git-poller-provides': 
            file        => '/var/www/gitorious/doc/templates/ubuntu/git-poller',
            pattern     => 'Gitorious GIT',
            replacement => 'Gitorious-GIT',
            require     => Vcsrepo['/var/www/gitorious'],
        }

        ### stomp -- though we are using debian-installed stomp instead ###
        file { '/etc/init.d/stomp':
            ensure  => '/var/www/gitorious/doc/templates/ubuntu/stomp',
            require => Vcsrepo['/var/www/gitorious'],
        }
        common::replace { 'stomp-ruby-home': 
            file        => '/var/www/gitorious/doc/templates/ubuntu/stomp',
            pattern     => '\$RUBY_HOME/bin/ruby',
            replacement => '/usr/local/rvm/bin/rvm --with-rubies ree-1.8.7-2012.02\@gitorious do',
            require     => Vcsrepo['/var/www/gitorious'],
        }
        common::replace { 'stomp-gem-home': 
            file        => '/var/www/gitorious/doc/templates/ubuntu/stomp',
            pattern     => 'GEMS_HOME="/usr"',
            replacement => 'GEMS_HOME="`/usr/local/rvm/bin/rvm --with-rubies ree-1.8.7-2012.02\@gitorious do rvm gemdir`"',
            require     => Vcsrepo['/var/www/gitorious'],
        }

        ### Setup ultrasphinx ###
        file { '/etc/init.d/git-ultrasphinx':
            ensure  => '/var/www/gitorious/doc/templates/ubuntu/git-ultrasphinx',
            require => Vcsrepo['/var/www/gitorious'],
        }
        common::replace { 'git-ultrasphinx-rake': 
            file        => '/var/www/gitorious/doc/templates/ubuntu/git-ultrasphinx',
            pattern     => 'rake',
            replacement => '/usr/local/rvm/bin/rvm --with-rubies ree-1.8.7-2012.02\@gitorious do bundle exec rake',
            require     => Vcsrepo['/var/www/gitorious'],
        }
        common::replace { 'git-ultrasphinx-provides': 
            file        => '/var/www/gitorious/doc/templates/ubuntu/git-ultrasphinx',
            pattern     => 'Gitorious Ultrasphinx',
            replacement => 'Gitorious-Ultrasphinx',
            require     => Vcsrepo['/var/www/gitorious'],
        }

        ### Setup log rotation ###
        file { '/etc/logrotate.d/gitorious':
            ensure  => '/var/www/gitorious/doc/templates/ubuntu/gitorious-logrotate',
            require => Vcsrepo['/var/www/gitorious'],
        }

        ### Create pids dir that's somehow missing ###
        file { '/var/www/gitorious/tmp/pids':
            ensure  => directory,
            owner   => 'git',
            group   => 'gitorious',
            mode    => 775,
            require => Vcsrepo['/var/www/gitorious'],
        }

        ### Put gitorious on the PATH ###
        file { '/usr/local/bin/gitorious':
            ensure => '/var/www/gitorious/script/gitorious',
        }

        ### SSH stuff ###
        file { '/var/www/gitorious/.ssh':
            ensure => directory,
            owner  => 'git',
            group  => 'gitorious',
            mode   => 700,
        }
        file { '/var/www/gitorious/.ssh/authorized_keys':
            ensure  => present,
            owner   => 'git',
            group   => 'gitorious',
            mode    => 600,
            require => File['/var/www/gitorious/.ssh'],
        }

        ### This helps checking which execs have been executed in the post-install
        file { '/var/www/gitorious/steps':
            ensure => directory,
            owner  => "git",
            group  => "gitorious",
            mode   => 755,
            require => Vcsrepo['/var/www/gitorious'],
        }
    }

    # Configuration files for gitorious coming from puppet
    class config {
        file { '/var/www/gitorious/config/gitorious.yml':
            ensure  => present,
            owner   => 'git',
            group   => 'gitorious',
            mode    => 644,
            content => template('gitorious/gitorious.yml.erb'),
        }

        file { '/var/www/gitorious/config/broker.yml':
            ensure  => '/var/www/gitorious/config/broker.yml.example',
        }

        file { '/var/www/gitorious/config/database.yml':
            ensure  => present,
            owner   => 'git',
            group   => 'gitorious',
            mode    => 644,
            content => template('gitorious/database.yml.erb'),
        }

        file { '/etc/apache2/sites-available/gitorious':
            ensure  => present,
            owner   => 'root',
            group   => 'root',
            mode    => 644,
            content => template('gitorious/site.gitorious.erb'),
        }

        include production  # Set RAILS_ENV for all
    }

    # Post-install activities (basically, a bunch of chained execs)
    class post-install {
        exec { 'git submodule init && touch /var/www/gitorious/steps/submodule-init':
            alias   => 'submodule-init',
            user    => 'git',
            cwd     => '/var/www/gitorious',
            creates => '/var/www/gitorious/steps/submodule-init'
        }
        exec { 'git submodule update && touch /var/www/gitorious/steps/submodule-update':
            alias   => 'submodule-update',
            user    => 'git',
            cwd     => '/var/www/gitorious',
            require => Exec['submodule-init'],
            creates => '/var/www/gitorious/steps/submodule-update'
        }

        # We do these two with "su" to ensure a login session
#        exec { '/bin/su - git -c "rvm alias create default ree-1.8.7-2012.02@gitorious && touch /var/www/gitorious/steps/rvm-default"':
#            alias   => 'rvm-default',
#            creates => '/var/www/gitorious/steps/rvm-default'
#        }
        exec { '/bin/su - git -c "rvm --with-rubies ree-1.8.7-2012.02@gitorious do bundle install && touch /var/www/gitorious/steps/gitorious-bundle"':
            alias   => 'gitorious-bundle',
            require => [
#                Exec['rvm-default'],
                Exec['submodule-update'],
            ],
            creates => '/var/www/gitorious/steps/gitorious-bundle',
            timeout => 600,
            tries   => 3,
        }
        exec { '/bin/su - git -c "rvm --with-rubies ree-1.8.7-2012.02@gitorious do bundle pack && touch /var/www/gitorious/steps/gitorious-pack"':
            alias   => 'gitorious-pack',
            require => [
#                Exec['rvm-default'],
                Exec['submodule-update'],
                Exec['gitorious-bundle'],
            ],
            creates => '/var/www/gitorious/steps/gitorious-pack'
        }

        # Because the database is only created on the second run, so must this be only run on the second run
        if $mysql_exists == 'true' {
            # All of this stuff depends on rubygems, which depends on Puppet version >= 2.6.7
            if versioncmp($puppetversion, '2.6.7') >= 0 {
                exec { 'rm -f /var/www/gitorious/steps/rake-dbcreate /var/www/gitorious/steps/rake-dbmigrate /var/www/gitorious/steps/rake-ultrasphinx':
                    alias => 'reset-rake-tasks',
                    refreshonly => true,
                }
                # WARNING!!! This gives false positives for some reason.
                exec { '/bin/su - git -c "rvm --with-rubies ree-1.8.7-2012.02@gitorious do bundle exec rake db:create && touch /var/www/gitorious/steps/rake-dbcreate"':
                    alias       => 'rake-dbcreate',
                    require     => [
                        Mysql_database['gitorious'],
                        Mysql::Rights['Gitorious access to database'],
                        Exec['gitorious-bundle'],
                        Exec['submodule-update'],
                        Exec['rubygems'],
                    ],
                    creates     => '/var/www/gitorious/steps/rake-dbcreate'
                }
                exec { '/bin/su - git -c "rvm --with-rubies ree-1.8.7-2012.02@gitorious do bundle exec rake db:migrate && touch /var/www/gitorious/steps/rake-dbmigrate"':
                    alias       => 'rake-dbmigrate',
                    require     => [
                        Mysql_database['gitorious'],
                        Mysql::Rights['Gitorious access to database'],
                        Exec['rake-dbcreate'],
                        Exec['submodule-update'],
                        Exec['rubygems'],
                    ],
                    creates     => '/var/www/gitorious/steps/rake-dbmigrate'
                }
                exec { '/bin/su - git -c "rvm --with-rubies ree-1.8.7-2012.02@gitorious do bundle exec rake ultrasphinx:bootstrap && touch /var/www/gitorious/steps/rake-ultrasphinx"':
                    alias       => 'rake-ultrasphinx',
                    require     => [
                        Exec['rake-dbmigrate'],
                        Exec['gitorious-bundle'],
                        Exec['submodule-update'],
                        Exec['rubygems'],
                    ],
                    creates     => '/var/www/gitorious/steps/rake-ultrasphinx'
                }
                common::replace { 'git-ultrasphinx-dbconf': 
                    file        => '/var/www/gitorious/config/ultrasphinx/production.conf',
                    pattern     => 'base_tags',
                    replacement => 'tags',
                    require     => [
                        Vcsrepo['/var/www/gitorious'],
                        Exec['rake-ultrasphinx'],
                    ],
                }

                # Cron stuff
                cron { 'ultrasphinx-index':
                    ensure  => present,
                    command => 'cd /var/www/gitorious && /usr/local/rvm/bin/rvm --with-rubies ree-1.8.7-2012.02@gitorious do bundle exec rake ultrasphinx:index RAILS_ENV=production',
                    user    => 'git',
                    require => [
                        Exec['rake-ultrasphinx'],
                        Common::Replace['git-ultrasphinx-dbconf'],
                    ],
                }
            }
        }
        # Web stuff
        exec { 'a2dissite default && touch /var/www/gitorious/steps/disable-default':
            creates => '/var/www/gitorious/steps/disable-default'
        }
        exec { 'a2dissite default-ssl && touch /var/www/gitorious/steps/disable-default-ssl':
            creates => '/var/www/gitorious/steps/disable-default-ssl'
        }
        exec { 'a2ensite gitorious && touch /var/www/gitorious/steps/enable-gitorious':
            creates => '/var/www/gitorious/steps/enable-gitorious',
            require => File['/etc/apache2/sites-available/gitorious'],
        }
    }

    # Gitorious services -- this really needed require dependencies
    class services {
        service { 'apache2':
            ensure  => running,
            enable  => true,
        }

        # Avoid enabling gitorious services before the database has a chance to be created
        if $mysql_exists == 'true' {
            service { 'git-daemon':
                ensure    => running,
                enable    => true,
                hasstatus => false,
            }

            # We are using Debian-installed stompserver
            service { 'stomp':
                ensure    => stopped,
                enable    => false,
                hasstatus => false,
                pattern   => 'stomp\b',
            }

            service { 'git-ultrasphinx':
                ensure  => running,
                enable  => true,
                require => Common::Replace['git-ultrasphinx-dbconf'],
            }

            service { 'git-poller':
                ensure    => running,
                enable    => true,
                hasstatus => false,
                pattern   => 'gitorious-poller',
            }
        }
    }
}

# vim: set ts=4 sw=4 et:
