#!perl -T
use strict;
use warnings;
use ExtUtils::PkgConfig ();
use File::Spec;
use File::Temp qw(tempfile);
use Test::More;
use Test::Exception;

BEGIN {
    eval 'use Test::Taint 1.06';
    plan skip_all => 'Test::Taint 1.06 required for testing behaviors on tainted inputs' if $@;
};

BEGIN {
    eval 'use Taint::Util 0.08 qw(untaint)';
    plan skip_all => 'Taint::Util 0.08 required for testing behaviors on tainted inputs' if $@;
};

my ($key, $crt);
do {
    # What can we do other than this...?
    untaint $ENV{PATH};

    my $OPENSSL = ExtUtils::PkgConfig->variable('openssl', 'prefix') . '/bin/openssl';
    if (-x $OPENSSL) {
        untaint $OPENSSL;
        diag "Using `$OPENSSL' to generate a keypair";
    }
    else {
        BAIL_OUT(q{Executable `openssl' was not found});
    }

    my ($conf_fh, $conf_file) = tempfile(UNLINK => 1);
    print {$conf_fh} <<'EOF';
[ req ]
distinguished_name     = req_distinguished_name
attributes             = req_attributes
prompt                 = no
[ req_distinguished_name ]
C                      = AU
ST                     = Some-State
L                      = Test Locality
O                      = Organization Name
OU                     = Organizational Unit Name
CN                     = Common Name
emailAddress           = test@email.address
[ req_attributes ]
EOF
    close $conf_fh;

    my $DEVNULL = File::Spec->devnull();
    my (undef, $key_file) = tempfile(UNLINK => 1);
    my (undef, $csr_file) = tempfile(UNLINK => 1);
    my (undef, $crt_file) = tempfile(UNLINK => 1);

    system(qq{$OPENSSL genrsa -out $key_file >$DEVNULL 2>&1}) and die $!;
    system(qq{$OPENSSL req -new -key $key_file -out $csr_file -config $conf_file >$DEVNULL 2>&1}) and die $!;
    system(qq{$OPENSSL x509 -in $csr_file -out $crt_file -req -signkey $key_file -set_serial 1 >$DEVNULL 2>&1}) and die $!;

    $key = do {
        local $/;
        open my $fh, '<', $key_file or die $!;
        scalar <$fh>;
    };
    $crt = do {
        local $/;
        open my $fh, '<', $crt_file or die $!;
        scalar <$fh>;
    };
};

my $plain = q{From: alice@example.org
To: bob@example.org
Subject: Crypt::SMIME test

This is a test mail. Please ignore...
};
$plain =~ s/\r?\n|\r/\r\n/g;
my $verify = q{Subject: Crypt::SMIME test

This is a test mail. Please ignore...
};
$verify =~ s/\r?\n|\r/\r\n/g;
#-----------------------

BEGIN {
    plan tests => 6;

    use_ok('Crypt::SMIME');
}

taint_checking_ok();

subtest 'Untainted' => sub {
    plan tests => 14;

    my $smime = Crypt::SMIME->new();
    untaint $key;
    untaint $crt;
    lives_ok {$smime->setPrivateKey($key, $crt)} 'Set an untainted keypair';
    lives_ok {$smime->setPublicKey($crt)} 'Set un untainted public key';
    lives_ok {$smime->setPublicKey([$crt])} 'Set un untainted public key';

    my $signed;
    untaint $plain;
    lives_ok {$signed = $smime->sign($plain)} 'Sign an untainted message';
    untainted_ok $signed, 'The signed message shall be untainted';
    lives_and {
        ok $smime->isSigned($signed)
    } 'isSigned() on an untainted signed message shall succeed';

    my $verified;
    lives_ok {$verified = $smime->check($signed)} 'Verify an untainted message';
    untainted_ok $verified, 'The verified message shall be untainted';

    my $encrypted;
    lives_ok {$encrypted = $smime->encrypt($plain)} 'Encrypt an untainted message';
    untainted_ok $encrypted, 'The encrypted message shall be untainted';
    lives_and {
        ok $smime->isEncrypted($encrypted);
    } 'isEncrypted() on an untainted encrypted message shall succeed';

    my $decrypted;
    lives_ok {$decrypted = $smime->decrypt($encrypted)} 'Decrypt an untainted message';
    untainted_ok $decrypted, 'The decrypted message shall be untainted';
    is $decrypted, $verify, 'The decrypted message matches to the original'
};

subtest 'Tainted keypair' => sub {
    plan tests => 13;

    my $smime = Crypt::SMIME->new();
    taint $key;
    taint $crt;
    lives_ok {$smime->setPrivateKey($key, $crt)} 'Set an tainted keypair';
    untaint $crt;
    lives_ok {$smime->setPublicKey($crt)} 'Set un untainted public key';
    lives_ok {$smime->setPublicKey([$crt])} 'Set un untainted public key';

    my $signed;
    untaint $plain;
    lives_ok {$signed = $smime->sign($plain)} 'Sign an untainted message';
    tainted_ok $signed, 'The signed message shall be tainted';

    my $verified;
    untaint $signed;
    lives_ok {$verified = $smime->check($signed)} 'Verify an untainted message';
    untainted_ok $verified, 'The verified message shall be untainted';

    my $encrypted;
    lives_ok {$encrypted = $smime->encrypt($plain)} 'Encrypt an untainted message';
    untainted_ok $encrypted, 'The encrypted message shall be untainted';
    lives_and {
        ok $smime->isEncrypted($encrypted);
    } 'isEncrypted() on an untainted encrypted message shall succeed';

    my $decrypted;
    lives_ok {$decrypted = $smime->decrypt($encrypted)} 'Decrypt an untainted message';
    tainted_ok $decrypted, 'The decrypted message shall be tainted';
    is $decrypted, $verify, 'The decrypted message matches to the original'
};

subtest 'Tainted plain text' => sub {
    plan tests => 13;

    my $smime = Crypt::SMIME->new();
    untaint $key;
    untaint $crt;
    lives_ok {$smime->setPrivateKey($key, $crt)} 'Set an untainted keypair';
    lives_ok {$smime->setPublicKey($crt)} 'Set an untainted public key';
    lives_ok {$smime->setPublicKey([$crt])} 'Set an untainted public key';

    my $signed;
    taint $plain;
    lives_ok {$signed = $smime->sign($plain)} 'Sign a tainted message';
    tainted_ok $signed, 'The signed message shall be tainted';

    my $verified;
    lives_ok {$verified = $smime->check($signed)} 'Verify a tainted message';
    tainted_ok $verified, 'The verified message shall be tainted (because we haven\'t verified the cleanliness of message itself)';

    my $encrypted;
    lives_ok {$encrypted = $smime->encrypt($plain)} 'Encrypt a tainted message';
    tainted_ok $encrypted, 'The encrypted message shall be tainted';
    lives_and {
        ok $smime->isEncrypted($encrypted);
    } 'isEncrypted() on a tainted encrypted message shall succeed';

    my $decrypted;
    lives_ok {$decrypted = $smime->decrypt($encrypted)} 'Decrypt a tainted message';
    tainted_ok $decrypted, 'The decrypted message shall be tainted';
    is $decrypted, $verify, 'The decrypted message matches to the original'
};

subtest 'Tainted public keys' => sub {
    plan tests => 13;

    my $smime = Crypt::SMIME->new();
    untaint $key;
    untaint $crt;
    lives_ok {$smime->setPrivateKey($key, $crt)} 'Set an untainted keypair';
    taint $crt;
    lives_ok {$smime->setPublicKey($crt)} 'Set a tainted public key';
    lives_ok {$smime->setPublicKey([$crt])} 'Set a tainted public key';

    my $signed;
    untaint $plain;
    lives_ok {$signed = $smime->sign($plain)} 'Sign an untainted message';
    tainted_ok $signed, 'The signed message shall be tainted (because we signed it with a tainted key)';

    my $verified;
    untaint $signed;
    lives_ok {$verified = $smime->check($signed)} 'Verify an untainted message';
    tainted_ok $verified, 'The verified message shall be tainted (because we verified it with a tainted key)';

    my $encrypted;
    lives_ok {$encrypted = $smime->encrypt($plain)} 'Encrypt an untainted message';
    tainted_ok $encrypted, 'The encrypted message shall be tainted (because we encrypted it with a tainted key)';
    lives_and {
        ok $smime->isEncrypted($encrypted);
    } 'isEncrypted() on a tainted encrypted message shall succeed';

    my $decrypted;
    lives_ok {$decrypted = $smime->decrypt($encrypted)} 'Decrypt a tainted message';
    tainted_ok $decrypted, 'The decrypted message shall be tainted';
    is $decrypted, $verify, 'The decrypted message matches to the original'
};
