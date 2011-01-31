#!/usr/bin/perl
use strict;
use IO::Socket;
use re 'eval';

#---
sub timestamp {
	my ($param) = @_;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	if ($param eq "brain") { return sprintf("%04d.%02d.%02d at %02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec); }
	else { return sprintf("(%02d:%02d:%02d) ",$hour,$min,$sec); }
}
#---
use constant {
	VERSION => "v0.2",

	ui_recv 	=> chr(27) . "[0m" . timestamp() . chr(27) . "[1m" . chr(27) . "[34m" . "[>]" . chr(27) . "[0m ", #azul
	ui_send		=> chr(27) . "[0m" . timestamp() . chr(27) . "[1m" . chr(27) . "[32m" . "[<]" . chr(27) . "[0m ", #verde
	ui_error 	=> chr(27) . "[0m" . timestamp() . chr(27) . "[1m" . chr(27) . "[31m" . "[E]" . chr(27) . "[0m ", #vermelho
	ui_warn		=> chr(27) . "[0m" . timestamp() . chr(27) . "[1m" . chr(27) . "[33m" . "[!]" . chr(27) . "[0m ", #amarelo
	ui_msg		=> chr(27) . "[0m" . timestamp() . chr(27) . "[35m" . "[*]" . chr(27) . "[0m ", #roxo

	ui_raw_r	=> chr(27) . "[1m" . chr(27) . "[34m" . "[RAW]" . chr(27) . "[0m ",
	ui_raw_s	=> chr(27) . "[1m" . chr(27) . "[32m" . "[RAW]" . chr(27) . "[0m ",
	
	ui_ctcp		=> chr(27) . "[1m" . chr(27) . "[31mCTCP "
};
#---
my $socket;
sub sendmsg {
	my ($target,$msg) = @_;
	print $socket "PRIVMSG $target :$msg\n";
}
sub sendaction {
	my ($target,$msg) = @_;
	print $socket "PRIVMSG $target :" . chr(1) . "ACTION $msg" . chr(1) . "\n";
}
sub sendctcp {
	my ($target,$ctcp,$msg) = @_;
	print $socket "PRIVMSG $target :" . chr(1) . uc($ctcp) . " $msg" . chr(1) . "\n";
}
sub sendctcp_reply {
	my ($target,$ctcp,$msg) = @_;
	print $socket "NOTICE $target :" . chr(1) . uc($ctcp) . " $msg" . chr(1) . "\n";
}
#---
my %config;
my $confighandle;
my $configfile;
if ($ARGV[0]) { $configfile = $ARGV[0]; }
else { $configfile = 'hayas.conf'; }
open($confighandle,$configfile);
while (<$confighandle>) {
	chomp $_;
	my @temp = split('=',$_);
	if (@temp[0] eq "server") { $config{server} = @temp[1]; }
	elsif (@temp[0] eq "port") { $config{port} = @temp[1]; }
	elsif (@temp[0] eq "nick") { $config{nick} = @temp[1]; }
	elsif (@temp[0] eq "username") { $config{username} = @temp[1]; }
	elsif (@temp[0] eq "realname") { $config{realname} = @temp[1]; }
	elsif (@temp[0] eq "chan") { $config{chan} = @temp[1]; }
	elsif (@temp[0] eq "adminhosts") { $config{adminhosts} = @temp[1]; }
	elsif (@temp[0] eq "mode") { $config{mode} = @temp[1]; }
	elsif (@temp[0] eq "brain") { $config{brain} = @temp[1]; }
	elsif (@temp[0] eq "markov") { $config{markov} = @temp[1]; }
	elsif (@temp[0] eq "learning") { $config{learning} = @temp[1]; }
	elsif (@temp[0] eq "showraw") { $config{showraw} = @temp[1]; }
}
close($confighandle);
#---
my %markov;
my $markovhandle;
sub markovget {
	my ($target,$index) = @_;
	my @matches;
	my $i = 0;
	open($markovhandle,$config{markov});
	while (<$markovhandle>) {
		chomp $_;
		my @temp = split('\t', $_);
		if (@temp[0] eq $target) { @matches[$i++] = @temp[$index]; }
	}
	close $markovhandle;
	
	my $match;
	while ((!($match = @matches[int(rand(@matches)-1)])) && (@matches > 1)) { $match = @matches[int(rand(@matches)-1)]; }
	return $match;
}

sub markovphrase {
	($markov{base}) = @_; #palavra de base
	$markov{word} = $markov{base}; #palavra atual
	$markov{length} = int((rand(8)+8)+1); #numero de palavras (8-16)
	$markov{basepos} = int(rand($markov{length})); #posicao da palavra de base
	$markov{phrase} = $markov{word}; #meio-fim
	
	for ($markov{pos} = $markov{basepos}+1; $markov{pos} <= $markov{length}; $markov{pos}++) {
		$markov{word} = markovget($markov{word},2);
		if ($markov{word}) { $markov{phrase} = $markov{phrase} . " " . $markov{word}; }
		else { last; }
	}
	$markov{word} = $markov{base}; #inicio-meio
	for ($markov{pos} = $markov{basepos}-1; $markov{pos} > 0; $markov{pos}--) {
		$markov{word} = markovget($markov{word},1);
		if ($markov{word}) { $markov{phrase} = $markov{word} . " " . $markov{phrase}; }
		else { last; }
	}
	
	if (!($markov{phrase} eq $markov{base})) { return $markov{phrase}; }
	else { return; }
}
#---


print chr(27) . "[2J" . chr(27) . "[2;1H";
print chr(27) . "[0m" . chr(27) . "[33m" . "--" . chr(27) . "[0m" . chr(27) . "[1m" . " Hayas " . VERSION . chr(27) . "[0m" . chr(27) . "[33m " . ( "-" x (length("Config file: $configfile") - 10 - length(VERSION)) ) . "\n";
print chr(27) . "[0m" . "Config file: " . chr(27) . "[1m" . $configfile . "\n";
print chr(27) . "[0m" . chr(27) . "[33m" . ( "-" x length("Config file: $configfile") );
print chr(27) . "[0m\n\n";

print ui_msg . "Conectando a $config{server}:$config{port}...\n";

$socket = IO::Socket::INET->new(PeerAddr => $config{server},
								PeerPort => $config{port},
								Proto => 'tcp')
								or die ui_error . "Nao foi possivel conectar no servidor: $@";

print ui_msg . "Conectado!\n";

my $buffer;
my @raw;
my @params;
my %brain;
my $brainhandle;

while ($buffer = <$socket>) {
	@raw = split(' ',$buffer);
	
	if ($config{showraw} eq "1") { print ui_recv . ui_raw_r . "$buffer"; }
	
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
		
		#action messages
		if ((substr($message,0,8) eq chr(1) . "ACTION ") && (substr($message,-1,1) eq chr(1))) {
			$message = substr($message,8,-1);
			@params = split(' ',$message);
			
			print chr(27) . "[0m" . timestamp() . chr(27) . "[1m[$target]" . chr(27) . "[35m * $nick $message\n";
			if ($target eq $config{nick}) { $target = $nick; }
			
			next;
		}
		
		#ctcp messages
		elsif ((substr($message,0,1) eq chr(1)) && (substr($message,-1,1) eq chr(1))) {
			$message = substr($message,1,-1);
			@params = split(' ',$message);
			print ui_recv . ui_ctcp . "$nick: $message\n";
			
			if (@params[0] eq "VERSION") {
				sendctcp_reply($nick,"VERSION","Hayas " . VERSION . " by thoso");
			}
			
			next;
		}
		
		#normal messages
		@params = split(' ',$message);
		
		print chr(27) . "[0m" . timestamp() . chr(27) . "[1m[$target]" . chr(27) . "[1m <$nick> $message\n";
		if ($target eq $config{nick}) { $target = $nick; }

		#admin commands
		if ($hostname =~ /$config{adminhosts}/) {
			if (@params[0] eq "_quit") {
				sendmsg($target,"Aye （・Ａ・）");
				print ui_warn . "$nick ordenou desligamento\n";
				print $socket "QUIT :щ(ﾟДﾟщ)\n";
			}
			elsif (@params[0] eq "_join") { print $socket "JOIN @params[1]\n";	}
			elsif (@params[0] eq "_part") { print $socket "PART @params[1] :@params[2]\n"; }
			elsif (@params[0] eq "_nick") { print $socket "NICK @params[1]\n"; }
			elsif (@params[0] eq "_msg") {
				sendmsg(@params[1],substr("@params[2..@params]",0,-1));
				print ui_send . "[@params[1]] <$config{nick}> " . substr("@params[2..@params]",0,-1) . "\n";
			}
			elsif (@params[0] eq "_ctcp") {
				sendctcp(@params[1],uc(@params[2]), substr("@params[3..@params]",0,-1));
				print ui_send . ui_ctcp . "@params[1]: " . uc(@params[2]) . substr("@params[3..@params]",0,-1) . "\n";
			}
			elsif (@params[0] eq "_raw") {
				print $socket substr("@params[1..@params]",0,-1) . "\n";
				print ui_send . ui_raw_s . substr("@params[1..@params]",0,-1) . "\n";
			}
			elsif (@params[0] eq "_mode") {
				$config{mode} = @params[1];
				sendmsg($target,"Aye.");
			}
			elsif (@params[0] eq "_learning") {
				$config{learning} = @params[1];
				sendmsg($target,"Aye.");
			}
			elsif (@params[0] eq "_showraw") {
				$config{showraw} = @params[1];
				sendmsg($target,"Aye.");
			}
		}
		
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
		else {
			#markov's chain learning
			if (($config{learning} eq "1") && !(substr(@params[0],0,1) eq "_") && !($message =~ /(?i)$config{nick}/)){
				open($markovhandle,">>$config{markov}");
				print $markovhandle "@params[0]\t\t@params[1]\n";
				for (my $i = 1; $i < @params-1; $i++) {
					print $markovhandle "@params[$i]\t@params[$i-1]\t@params[$i+1]\n";
				}
				if (@params > 1) { print $markovhandle @params[@params-1] . "\t" . @params[@params-2] . "\t\n"; }
				close $markovhandle;
			}
		
			$buffer = $message;
		
			#regex stuff
			if (($config{mode} eq "1") || ($config{mode} eq "3")) {
				open($brainhandle, $config{brain});
				while (<$brainhandle>) {
					chomp $_;
					my @temp = split('\t', $_);
					$brain{lastwho} = @temp[0];
					$brain{lastwhen} = @temp[1];
					$brain{type} = @temp[2];
					$brain{regex} = @temp[3];
					$brain{response} = substr("@temp[4..@temp]",0,-1);
					
					$brain{regex} =~ s/\&ME/$config{nick}/g;
					$brain{regex} =~ s/\&NICK/$nick/g;
					$brain{regex} =~ s/\&TARGET/$target/g;
					
					$brain{response} =~ s/\&ME/$config{nick}/g;
					$brain{response} =~ s/\&NICK/$nick/g;
					$brain{response} =~ s/\&TARGET/$target/g;
					
					if ($message =~ /$brain{regex}/) {
						if ($brain{type} eq "M") {
							sendmsg($target,$brain{response});
							print ui_send . "[$target] <$config{nick}> $brain{response}\n";
						}
						elsif ($brain{type} eq "S") {
							$message =~ s/$brain{regex}/$brain{response}/g;
							sendmsg($target,$message);
							print ui_send . "[$target] <$config{nick}> $message\n";
						}
					}
				}
				close $brainhandle;
			}
			
			$message = $buffer;
			
			#markov's chain activation
			if (($config{mode} eq "2") || ($config{mode} eq "3")) {
				if  ($message =~ /(?i)$config{nick}/) {
					$message =~ s/[,]|[\.]|[!]|[\?]|[:]//g; #removendo pontuacao
					$message =~ s/(?i)$config{nick}//g; #removendo nick
					@params = split(' ',$message);
					$message = markovphrase(@params[int(rand(@params))]);					
					if (!$message) {
						for (my $i = 0; $i < @params; $i++) {
							$message = markovphrase(@params[$i]);
							if ($message) { last; }
						}
					}
					if ($message) {
						sendmsg($target,$message);
						print ui_send . "[$target] <$config{nick}> $message\n";
					}
				}
				elsif (@params[0] eq "_markov") {
					$message = markovphrase(@params[1]);
					sendmsg($target,$message);
					print ui_send . "[$target] <$config{nick}> $message\n";
				}
			}
		}
	}
}
close $socket;
print ui_warn . "Desconectado\n";