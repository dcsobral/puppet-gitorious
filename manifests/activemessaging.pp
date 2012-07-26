class gitorious::activemessaging {
    if $gitorious::useActiveMQ {
        include gitorious::activemessaging::activemq
        package { 'stompserver': ensure => absent, }
    } else {
        include gitorious::activemessaging::stompserver
        package { 'activemq': ensure => absent, }
    }

    # ActiveMQ
    class activemq {
        include source-wheezy
        package { 'activemq': ensure => installed, }
        apt::preferences { [ 'libcommons-lang-java', 'liblog4j1.2-java', 'libxbean-java', ]:
            ensure   => present,
            pin      => 'release a=testing',
            priority => 990,
        }
        file { '/etc/activemq/instances-available/main/activemq.xml':
            ensure  => present,
            owner   => 'root',
            group   => 'root',
            mode    => 644,
            source  => 'puppet:///gitorious/activemq/activemq.xml',
            require => Package['activemq'],
            notify  => Service['activemq'],
        }
        file { '/etc/activemq/instances-enabled/main':
            ensure  => '/etc/activemq/instances-available/main',
            require => Package['activemq'],
            notify  => Service['activemq'],
        }
        service { 'activemq':
            ensure  => running,
            enable  => true,
            require => Package['activemq'],
        }
    }

    # Stompserver
    class stompserver {
        package { 'stompserver': ensure => installed, }
    }
}

# vim: set ts=4 sw=4 et:
