#!/usr/bin/perl
use strict;
use IO::Socket;

sub timestamp {
	my ($param) = @_;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	if ($param eq "brain") { return sprintf("%04d.%02d.%02d at %02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec); }
	else { return sprintf("(%02d:%02d:%02d) ",$hour,$min,$sec); }
}

use constant {
  ui_recv 	=> timestamp() . chr(27) . "[1m" . chr(27) . "[34m" . "[>]" . chr(27) . "[0m ", #azul
  ui_send 	=> timestamp() . chr(27) . "[1m" . chr(27) . "[32m" . "[<]" . chr(27) . "[0m ", #verde
  ui_error 	=> timestamp() . chr(27) . "[1m" . chr(27) . "[31m" . "[E]" . chr(27) . "[0m ", #vermelho
  ui_warn	=> timestamp() . chr(27) . "[1m" . chr(27) . "[33m" . "[!]" . chr(27) . "[0m ", #amarelo
  ui_msg	=> timestamp() . chr(27) . "[35m" . "[*]" . chr(27) . "[0m " #roxo
};

my %config;
my $socket;

sub sendmsg {
  my ($target,$msg) = @_;
  print $socket "PRIVMSG $target :$msg\n";
}

#---
my $confighandle;
if ($ARGV[0]) { open($confighandle, $ARGV[0]); }
else { open($confighandle, 'ircbot.conf'); }
while (<$confighandle>) {
	chomp $_;
	my @temp = split('=',$_);
	if (@temp[0] eq "server") { $config{server} = @temp[1]; }
	elsif (@temp[0] eq "port") { $config{port} = @temp[1]; }
	elsif (@temp[0] eq "nick") { $config{nick} = @temp[1]; }
	elsif (@temp[0] eq "username") { $config{username} = @temp[1]; }
	elsif (@temp[0] eq "realname") { $config{realname} = @temp[1]; }
	elsif (@temp[0] eq "chan") { $config{chan} = @temp[1]; }
	elsif (@temp[0] eq "brain") { $config{brain} = @temp[1]; }
}
close($confighandle);
#---

print ui_msg . "Conectando a $config{server}:$config{port}...\n";

$socket = IO::Socket::INET->new(PeerAddr => $config{server},
								PeerPort => $config{port},
								Proto => 'tcp')
								or die ui_error . "Nao foi poss�vel conectar no servidor: $@";

print ui_msg . "Conectado!\n";

my $buffer;
my @raw;
my @params;
my %brain;
my $brainhandle;

while ($buffer = <$socket>) {
	@raw = split(' ',$buffer);
	
	if (@raw[1] eq "NOTICE") {
		if (@raw[2] eq "AUTH") {
			if (substr("@raw[3..@raw]",0,-1) eq ":*** Looking up your hostname...") {
				print ui_msg . "Autenticando...\n";
				print $socket "NICK $config{nick}\n";
				print $socket "USER $config{username} 8 * :$config{realname}\n";
				print ui_send . "$config{nick} ($config{realname})\n";
			}
		}
	}
	elsif (@raw[1] eq "433") { #nick is already in use
		print ui_warn . "Nick $config{nick} em uso! Alterando para $config{nick}_...\n";
		$config{nick} = $config{nick} . "_";
		print $socket "NICK $config{nick}\n";
	}
	elsif (@raw[1] eq "376") { #end of motd
		print $socket "JOIN $config{chan}\n";
		print ui_msg . "Entrando nos canais... ($config{chan})\n";
	}
	elsif (@raw[0] eq "PING") { #staying alive
		print ui_recv . "Ping?\n";
		print $socket "PONG " . substr("@raw[3..@raw]",0,-1) . "\n";
		print ui_send . "Pong!\n";
	}
	elsif (@raw[1] eq "PRIVMSG") {
		my ($nick,$hostname) = (@raw[0] =~ /:([^!]+)!([^ ]+)/);
		my $target = @raw[2];
		my $message = substr("@raw[3..@raw]",1,-1);
		@params = split(' ',$message);
		
		print chr(27) . "[0m" . timestamp() . chr(27) . "[1m[$target]" . chr(27) . "[1m <$nick> $message\n";
		if ($target eq $config{nick}) { $target = $nick; }
		
		#commands
		if (@params[0] eq "_last") {
			if ($brain{lastwho}) { sendmsg($target,"$brain{lastwho} in $brain{lastwhen}"); }
		}
		elsif (@params[0] eq "_learn") {
			open($brainhandle, ">>$config{brain}");
			print $brainhandle "$nick" . "\t" . timestamp("brain") . "\t" . @params[1] . "\t" . @params[2] . "\t" . substr("@params[3..@params]",0,-1) . "\n";
			close($brainhandle);
			sendmsg($target,"Aye!");
		}
		elsif (@params[0] eq "_regex") {
			if (substr("@params[2..@params]",0,-1) =~ /@params[1]/) { sendmsg($target,"$nick: Regex Match!"); }
		}
		
		#admin commands
		elsif ($hostname eq '~uki@wormhole.in.my.mind') {
			if (@params[0] eq "_quit") {
				sendmsg($target,"hai （・Ａ・）");
				print ui_warn . "$nick ordenou desligamento\n";
				print $socket "QUIT :щ(ﾟДﾟщ)\n";
			}
			elsif (@params[0] eq "_join") { print $socket "JOIN @params[1]\n";	}
			elsif (@params[0] eq "_part") { print $socket "PART @params[1] :@params[2]\n"; }
			elsif (@params[0] eq "_nick") { print $socket "NICK @params[1]\n"; }
			elsif (@params[0] eq "_say") { sendmsg(@params[1],substr("@params[2..@params]",0,-1)); }
			elsif (@params[0] eq "_raw") { print $socket substr("@params[1..@params]",0,-1); }
		}
		
		#regex stuff
		open($brainhandle, $config{brain});
		while (<$brainhandle>) {
			chomp $_;
			my @temp = split('\t', $_);
			$brain{lastwho} = @temp[0];
			$brain{lastwhen} = @temp[1];
			$brain{type} = @temp[2];
			$brain{regex} = @temp[3];
			$brain{response} = substr("@temp[4..@temp]",0,-1);
			
			while ($brain{regex} =~ s/\&ME/$config{nick}/) { };
			while ($brain{regex} =~ s/\&NICK/$nick/) { };
			while ($brain{regex} =~ s/\&TARGET/$target/) { };
			
			while ($brain{response} =~ s/\&ME/$config{nick}/) { };
			while ($brain{response} =~ s/\&NICK/$nick/) { };
			while ($brain{response} =~ s/\&TARGET/$target/) { };
			
			if ($message =~ /$brain{regex}/) {
				if ($brain{type} eq "M") { sendmsg($target,$brain{response}); }
				elsif ($brain{type} eq "S") {
					while ($message =~ s/$brain{regex}/$brain{response}/) { };
					sendmsg($target,$message);
				}
			}
			
		}
		close $brainhandle;
	}
}
close $socket;
print ui_warn . "Desconectado\n";