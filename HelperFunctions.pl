#!/usr/bin/perl

############ Printing Helper Function BEGIN ############

sub _stringify {
    my ($data) = @_;

    if (ref($data) eq 'ARRAY') {
        # Array reference: format as [a, b, c]
        return '[' . join(', ', map { _stringify($_) } @$data) . ']';
    }
    elsif (ref($data) eq 'HASH') {
        # Hash reference: format as {key => value, key2 => value2}
        return '{' . join(', ', map { "$_ => " . _stringify($data->{$_}) } sort keys %$data) . '}';
    }
    elsif (ref($data)) {
        # Other references (e.g. scalar refs, nested structures)
        return _stringify($$data);
    }
    else {
        # Plain scalar
        return defined $data ? $data : 'undef';
    }
}

sub println {
    # use sprintf in the arg if u need o/p in formatted manner 
    # sprintf("Name: %-10s | Age: %2d", $name, $age);
    foreach my $arg (@_) { print _stringify($arg) . "\n"; }
}

# ----------------------------
# Mail Utility Functions
# ----------------------------

sub send_mail {
        # Function to send an email using the sendmail Unix command

    my ($to, $from, $subject, $message_body) = @_;

    # Path to the sendmail executable; adjust if necessary for your system
    my $sendmail_path = '/usr/sbin/sendmail';

    # Open a pipe to the sendmail command
    open(MAIL, "|$sendmail_path -t -i") or die "Cannot open sendmail pipe: $!";

    # Print email headers
    print MAIL "To: $to\n";
    print MAIL "From: $from\n";
    print MAIL "Subject: $subject\n";
    print MAIL "Content-type: text/plain\n\n"; # Required for plain text body

    # Print email body
    print MAIL $message_body;

    # Close the pipe
    close(MAIL) or die "Error closing sendmail pipe: $!";

    print "Email sent successfully to $to\n";
}

my $MAIL_FROM = 'from@***';
my $MAIL_TO = 'to@***';
send_mail($MAIL_TO,$MAIL_FROM,'[Testing] Test mail','Please ignore');



my @fruits = ('apple', 'banana', 'cherry');
my %person = (name => 'Alice', age => 30, city => 'Paris');
my $nested = { colors => ['red', 'green', 'blue'], numbers => [1, 2, 3] };

my $name = 'Mohan' ; 
println("Hello $name !");
# For Printing Formatted O/p
println(sprintf("Name: %-10s | Age: %2d", $name , 40));
println(\@fruits);
println(\%person);
println($nested);

############ Printing Helper Function END ############
