require 'erb'
require 'uri'
require 'net/http'
require 'net/https'
require 'rubygems'

STDOUT.sync = true
BASEDIR = File.dirname(__FILE__)
PEVERSION = ENV['PEVERSION'] || '3.7.2'
PESTATUS = ENV['PESTATUS'] || 'release'
SRCDIR = ENV['SRCDIR'] || '/usr/src'
PUPPET_VER = '3.6.2'
FACTER_VER = '1.7.5'
HIERA_VER = '1.3.4'

$settings = Hash.new

hostos = `uname -s`

# Bail if handed a 'vmtype' that's not supported.
if ENV['vmtype'] && ENV['vmtype'] !~ /^(training|learning|student)$/
  abort("ERROR: Unrecognized vmtype parameter: #{ENV['vmtype']}")
end

desc "Print list of rake tasks"
task :default do
  system("rake -sT")  # s for silent
  cputs "NOTE: The usage of this Rakefile has changed.\n" + \
        "This is intended to be run within a blank VM to bootstrap it to the various Education VMs.\n" + \
        "To use this repo to provision a VM, refer to the files in the packer directory.\n"
end

desc "Install open source puppet for VM deployment"
task :standalone_puppet do

  cputs "Cloning puppet..."
  gitclone 'https://github.com/puppetlabs/puppet', "#{SRCDIR}/puppet", 'master', "#{PUPPET_VER}"

  cputs "Cloning facter..."
  gitclone 'https://github.com/puppetlabs/facter', "#{SRCDIR}/facter", 'master', "#{FACTER_VER}"

  cputs "Cloning hiera..."
  gitclone 'https://github.com/puppetlabs/hiera', "#{SRCDIR}/hiera", 'master', "#{HIERA_VER}"


  STDOUT.sync = true
  STDOUT.flush
end

desc "Training VM pre-install setup"
task :training_pre do
  # Set the dns info and hostname; must be done before puppet
  cputs "Setting hostname training.puppetlabs.vm"
  %x{hostname training.puppetlabs.vm}
  cputs  "Editing /etc/hosts"
  %x{sed -i "s/127\.0\.0\.1.*/127.0.0.1 training.puppetlabs.vm training localhost localhost.localdomain localhost4/" /etc/hosts}
  cputs "Editing /etc/sysconfig/network"
  %x{sed -ie "s/HOSTNAME.*/HOSTNAME=training.puppetlabs.vm/" /etc/sysconfig/network}
  %x{printf '\nsupersede domain-search "puppetlabs.vm";\n' >> /etc/dhcp/dhclient-eth0.conf}

end
desc "Learning VM pre-install setup"
task :learning_pre do
  # Set the dns info and hostname; must be done before puppet
  cputs "Setting hostname learning.puppetlabs.vm"
  %x{hostname learning.puppetlabs.vm}
  cputs  "Editing /etc/hosts"
  %x{sed -i "s/127\.0\.0\.1.*/127.0.0.1 learning.puppetlabs.vm localhost localhost.localdomain localhost4/" /etc/hosts}
  cputs "Editing /etc/sysconfig/network"
  %x{sed -ie "s/HOSTNAME.*/HOSTNAME=learning.puppetlabs.vm/" /etc/sysconfig/network}
  %x{printf '\nsupersede domain-search "puppetlabs.vm";\n' >> /etc/dhcp/dhclient-eth0.conf}

end

desc "Student VM pre-install setup"
task :student_pre do
  # Set the dns info and hostname; must be done before puppet
  cputs "Setting hostname student.puppetlabs.vm"
  %x{hostname student.puppetlabs.vm}
  cputs  "Editing /etc/hosts"
  %x{sed -i "s/127\.0\.0\.1.*/127.0.0.1 student.puppetlabs.vm training localhost localhost.localdomain localhost4/" /etc/hosts}
  cputs "Editing /etc/sysconfig/network"
  %x{sed -ie "s/HOSTNAME.*/HOSTNAME=student.puppetlabs.vm/" /etc/sysconfig/network}
  %x{printf '\nsupersede domain-search "puppetlabs.vm";\n' >> /etc/dhcp/dhclient-eth0.conf}
end

desc "Apply bootstrap manifest"
task :build do
 system('gem install r10k --no-RI --no-RDOC')
 Dir.chdir('/usr/src/puppetlabs-training-bootstrap') do
  system('RUBYLIB="/usr/src/puppet/lib:/usr/src/facter/lib:/usr/src/hiera/lib" PATH=$PATH:/usr/src/puppet/bin r10k puppetfile install')
 end
 system('RUBYLIB="/usr/src/puppet/lib:/usr/src/facter/lib:/usr/src/hiera/lib" /usr/src/puppet/bin/puppet apply --modulepath=/usr/src/puppetlabs-training-bootstrap/modules --verbose /usr/src/puppetlabs-training-bootstrap/manifests/site.pp')
end

desc "Post build cleanup tasks"
task :post do
  system('RUBYLIB="/usr/src/puppet/lib:/usr/src/facter/lib:/usr/src/hiera/lib" /usr/src/puppet/bin/puppet apply --modulepath=/usr/src/puppetlabs-training-bootstrap/modules --verbose /usr/src/puppetlabs-training-bootstrap/manifests/post.pp')
end

desc "Full Training VM Build"
task :training do
  cputs "Building Training VM"
  Rake::Task["standalone_puppet"].execute
  Rake::Task["training_pre"].execute
  Rake::Task["build"].execute
  Rake::Task["post"].execute
end

desc "Full Learning VM Build"
task :learning do
  cputs "Building Learning VM"
  Rake::Task["standalone_puppet"].execute
  Rake::Task["learning_pre"].execute
  Rake::Task["build"].execute
  Rake::Task["post"].execute
end

desc "Full Student VM Build"
task :student do
  cputs "Building Student VM"
  Rake::Task["standalone_puppet"].execute
  Rake::Task["student_pre"].execute
  Rake::Task["build"].execute
  Rake::Task["post"].execute
end

def download(url,path)
  u = URI.parse(url)
  net = Net::HTTP.new(u.host, u.port)
  case u.scheme
  when "http"
    net.use_ssl = false
  when "https"
    net.use_ssl = true
    net.verify_mode = OpenSSL::SSL::VERIFY_NONE
  else
    raise "Link #{url} is not HTTP(S)"
  end
  net.start do |http|
    File.open(path,"wb") do |f|
      begin
        http.request_get(u.path) do |resp|
          resp.read_body do |segment|
            f.write(segment)
          end
        end
      rescue => e
        cputs "Error: #{e.message}"
      end
    end
  end
end

def gitclone(source,destination,branch,tag = nil)
  if File.directory?(destination) then
    system("cd #{destination} && (git pull origin #{branch}") or raise(Error, "Cannot pull ${source}")
  else
    system("git clone #{source} #{destination} -b #{branch}") or raise(Error, "Cannot clone #{source}")
    system("cd #{destination} && git checkout #{tag}") if tag
  end
end

## Prompt for a response if a given ENV variable isn't set.
#
# args:
#   message:  the message you want displayed
#   varname:  the name of the environment variable to look for
#
# usage: update = env_prompt('Increment the release version? [Y/n]: ', 'RELEASE')
def env_prompt(message, varname)
  if ENV.include? varname
    ans = ENV[varname]
  else
    cprint message
    ans = STDIN.gets.strip
  end
  return ans
end

def verify_download(download, signature)
  crypto = GPGME::Crypto.new
  sign = GPGME::Data.new(File.open(signature))
  file_to_check = GPGME::Data.new(File.open(download))
  crypto.verify(sign, :signed_text => file_to_check, :always_trust => true) do |signature|
   puts "Valid!" if signature.valid?
  end
end

def cputs(string)
  puts "\033[1m#{string}\033[0m"
end

def cprint(string)
  print "\033[1m#{string}\033[0m"
end
# vim: set sw=2 sts=2 et tw=80 :
