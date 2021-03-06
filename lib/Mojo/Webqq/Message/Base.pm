package Mojo::Webqq::Message::Base;
use Mojo::Webqq::Base -base;
use Data::Dumper;
use Scalar::Util qw(blessed);
sub client {
    return $Mojo::Webqq::_CLIENT;
}
sub dump{
    my $self = shift;
    my $clone = {};
    my $obj_name = blessed($self);
    for(keys %$self){
        if(my $n=blessed($self->{$_})){
             $clone->{$_} = "Object($n)";
        }
        elsif($_ eq "member" and ref($self->{$_}) eq "ARRAY"){
            my $member_count = @{$self->{$_}};
            $clone->{$_} = [ "$member_count of Object(${obj_name}::Member)" ];
        }
        else{
            $clone->{$_} = $self->{$_};
        }
    }
    local $Data::Dumper::Indent = 1;
    local $Data::Dumper::Terse = 1;
    $self->client->print("Object($obj_name) " . Data::Dumper::Dumper($clone));
    return $self;
}

sub is_at{
    my $self = shift;
    my $object;
    my $displayname;
    if($self->class eq "recv"){
        $object = shift || $self->receiver;
        $displayname = $object->displayname;
    }
    elsif($self->class eq "send"){
        if($self->type eq "group"){
            $object = shift || $self->group->me;
            $displayname = $object->displayname;
        } 
        elsif($self->type eq "discuss"){
            $object = shift || $self->discuss->me;
            $displayname = $object->displayname;
        }
        elsif($self->type=~/^friend_message|sess_message$/){
            $object = shift || $self->receiver;
            $displayname = $object->displayname;
        }
    }
    return $self->content =~/\@\Q$displayname\E /; 
}

sub to_json_hash{
    my $self = shift;
    my $json = {};
    for my $key (keys %$self){
        next if substr($key,0,1) eq "_";
        if($key eq "sender"){
            $json->{sender} = $self->sender->displayname;
        }
        elsif($key eq "receiver"){
            $json->{receiver} = $self->receiver->displayname;
        }
        elsif($key eq "group"){
            $json->{group} = $self->group->displayname;
        }
        elsif($key eq "discuss"){
            $json->{discuss} = $self->discuss->displayname;
        }
        elsif(ref $self->{$key} eq ""){
            $json->{$key} = $self->{$key};
        }
    } 
    $json->{sender_uid} = $self->sender->uid;
    $json->{receiver_uid} = $self->receiver->uid;
    if($self->type eq "group_message"){
        $json->{group_uid} = $self->group->uid;
    }
    return $json;
}

sub text {
    my $self = shift;
    return $self->content if ref $self->raw_content ne "ARRAY";
    return join "",map{$_->{content}} grep {$_->{type} eq "txt"} @{$self->{raw_content}};
}

sub faces {
    my $self = shift;
    return if ref $self->raw_content ne "ARRAY";
    if(wantarray){
        return map {$_->{content}} grep {$_->{type} eq "face" or $_->{type} eq "emoji"} @{$self->{raw_content}};
    } 
    else{
        my @tmp = map {$_->{content}} grep {$_->{type} eq "face" or $_->{type} eq "emoji"} @{$self->{raw_content}};
        return \@tmp;
    }
}
sub images {
    my $self = shift;
    my $cb   = shift;
    $self->client->die("参数必须是一个函数引用") if ref $cb ne "CODE";
    return if ref $self->raw_content ne "ARRAY";
    return if $self->msg_class ne "recv";
    return if $self->type eq "discuss_message";
    for ( grep {$_->{type} eq "cface" or $_->{type} eq "offpic"} @{$self->raw_content}){
        if($_->{type} eq "cface"){
            return unless exists $_->{server};
            return unless exists $_->{file_id};
            return unless exists $_->{name};
            my ($ip,$port) = split /:/,$_->{server};
            $port = 80 unless defined $port;
            $self->client->_get_group_pic($_->{file_id},$_->{name},$ip,$port,$self->sender,$cb);
        }
        elsif($_->{type} eq "offpic"){
            $self->client->_get_offpic($_->{file_path},$self->sender,$cb);
        }
    }
}


sub reply {
    my $self = shift;
    $self->client->reply_message($self,@_);
}

sub is_success{
    my $self = shift;
    return $self->code == 0?1:0;
}

sub parse_send_status_msg{
    my $self = shift;
    my $json = shift;
    if(defined $json){
        if(exists $json->{errCode}){
            if($json->{errCode}==0 and exists $json->{msg} and $json->{msg} eq 'send ok'){
                $self->send_status(code=>0,msg=>"发送成功",info=>'发送正常');
            }
            elsif(exists $json->{errMsg} and $json->{errMsg} eq "ERROR"){
                $self->send_status(code=>-3,msg=>"发送失败",info=>'发送异常');
            }
            else{
                $self->send_status(code=>-4,msg=>"发送失败",info=>'响应未知: ' . $self->client->to_json($json));
            }
        }
        elsif(exists $json->{retcode}){
            if($json->{retcode}==0){
                $self->send_status(code=>0,msg=>"发送成功",info=>'发送正常');
            }
            elsif($json->{retcode}==1202){
                if($self->client->ignore_1202){
                    $self->send_status(code=>0,msg=>"发送成功",info=>'无法判断是否发送成功');
                }
                else{
                    $self->send_status(code=>-5,msg=>"发送失败",info=>'发送异常1202');
                }
            }
            else{
                $self->send_status(code=>-4,msg=>"发送失败",info=>'响应未知: ' . $self->client->to_json($json));
            }
        }
        else{
            $self->send_status(code=>-2,msg=>"发送失败",info=>'响应未知: ' . $self->cient->to_json($json));
        }
    }
    else{
        $self->send_status(code=>-1,msg=>"发送失败",info=>'数据格式错误'); 
    }
}

sub send_status{
    my $self = shift;
    my %opt = @_;
    $self->code($opt{code})->msg($opt{msg})->info($opt{info});
}
1;
