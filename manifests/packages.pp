class gitorious::packages {
    include git # See sample on README.mkd

    # System essentials
    package { 'git-svn': ensure => installed, } # git-core is deprecated
    package { 'apg': ensure => installed, } # Automated password generator
    package { [ 'libpcre3', 'libpcre3-dev', ]: ensure => installed, }
    package { [ 'build-essential', 'make', ]: ensure => installed, }
    package { [ 'zlib1g', 'zlib1g-dev', ]: ensure => installed, }
    package { [ 'aspell', 'aspell-br', ]: ensure => installed, }
    # we don't use sendmail, and ssh is dealt with elsewhere

    # Common packages
    package { 'libonig-dev': ensure => installed, } # Oniguruma regular expressions
    package { [ 'geoip-bin', 'libgeoip-dev', 'libgeoip1']: ensure => installed, }
    package { 'libyaml-dev': ensure => installed, }

    # Image manipulation
    package { [ 'imagemagick', 'libmagickwand-dev']: ensure => installed, }

    # Search
    package { 'sphinxsearch': ensure => installed, }

    ### Ruby/RVM ###
    # This *MUST* come last in packages!
    # RVM brings in a lot of packages, but it handles duplicates, while we don't
    include gitorious::packages::ruby # The ruby stuff is complex enough I decided to separate it into a package of its own
    class ruby {
        # A couple of external dependencies, not bundled
        package { 'libbluecloth-ruby': ensure => installed, } # markdown
        package { 'libopenssl-ruby1.8': ensure => installed, }

        # We use rvm to handle ruby needs
        include rvm
        group { 'rvm':
            ensure => present,
        }
        Group['rvm'] -> User <| |>
        Users::Massuseraccount <| tag == 'administrators' |> {
            groups => [ 'infra', 'rvm', ]
        }

        include apt::backports # rvm_* requires Puppet >= 2.6.7

        if versioncmp($puppetversion, '2.6.7') >= 0 {
            rvm_system_ruby { 'ree-1.8.7-2012.02':
                ensure => 'present',
                default_use => false;
            }
            rvm_gemset { "ree-1.8.7-2012.02@gitorious":
                ensure  => present,
                require => Rvm_system_ruby['ree-1.8.7-2012.02'],
            }
            exec { '/usr/local/rvm/bin/rvm --with-rubies ree-1.8.7-2012.02@gitorious rubygems 1.4.2':
                alias   => 'rubygems',
                unless  => 'test "`/usr/local/rvm/bin/rvm --with-rubies ree-1.8.7-2012.02@gitorious do gem -v`" = "1.4.2"',
                require => Rvm_gemset['ree-1.8.7-2012.02@gitorious'],
            }
            rvm_gem { 'rake@gitorious':
                name         => 'rake',
                alias        => 'rake',
                ensure       => '0.8.7',
                ruby_version => 'ree-1.8.7-2012.02@gitorious',
                require      => [
                    Rvm_gemset['ree-1.8.7-2012.02@gitorious'],
                    Exec['rubygems'],
                ],
            }
            rvm_gem { 'rake-0.8.7@global':
                name         => 'rake',
                ensure       => '0.8.7',
                ruby_version => 'ree-1.8.7-2012.02@global',
                require      => [
                    Rvm_system_ruby['ree-1.8.7-2012.02'],
                    Exec['rubygems'],
                ],
            }
            exec { '/usr/local/rvm/bin/rvm --with-rubies ree-1.8.7-2012.02@global do gem uninstall rake -v "0.9.2.2"':
               user    => 'git',
               onlyif  => '/usr/local/rvm/bin/rvm --with-rubies ree-1.8.7-2012.02@global do gem list rake | grep -q 0.9.2.2',
               require => Rvm_gem['rake-0.8.7@global'],
            }
            class { 'rvm::passenger::apache':
                version            => '3.0.13',
                ruby_version       => 'ree-1.8.7-2012.02@gitorious',
                mininstances       => '3',
                maxinstancesperapp => '0',
                maxpoolsize        => '30',
                spawnmethod        => 'smart-lv2',
                require            => [
                    Rvm_gem['rake'],
                    Rvm_gemset['ree-1.8.7-2012.02@gitorious'],
                    Rvm_system_ruby['ree-1.8.7-2012.02'],
                    Exec['rubygems'],
                ],
            }
            Rvm_gemset <| title == 'ree-1.8.7-2012.02@gitorious' |> -> Rvm_gem <| title == 'passenger' |>
        }
    }
}

# vim: set ts=4 sw=4 et:
