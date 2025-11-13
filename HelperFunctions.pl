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
