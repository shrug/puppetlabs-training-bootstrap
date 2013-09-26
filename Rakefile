require 'erb'
require 'uri'
require 'net/http'
require 'net/https'
require 'rubygems'
require 'gpgme'
require 'facter'

import 'utils.rake'
Dir.glob('tasks/*.rake').each { |r| import r }

STDOUT.sync = true
BASEDIR = File.dirname(__FILE__)
if ENV['USER'] == 'jenkins' || ENV['USER'] == 'root'
  SITESDIR = "/srv/builder/Sites"
else
  SITESDIR = ENV['HOME'] + "/Sites"
end
BUILDDIR = "#{SITESDIR}/build"
CACHEDIR = "#{SITESDIR}/cache"
KSISODIR = "#{BUILDDIR}/isos"
VAGRANTDIR = "#{BUILDDIR}/vagrant"
OVFDIR = "#{BUILDDIR}/ovf"
VMWAREDIR = "#{BUILDDIR}/vmware"
VBOXDIR = "#{BUILDDIR}/vbox"
# To build test VMs from CI builds,
# Download the PE installer (tar.gz) from the appropriate place:
# eg: http://neptune.puppetlabs.lan/3.0/ci-ready/
# to ~/Sites/cache/
# then,
# Edit the PEVERSION to something like:
# PEVERSION = '3.0.1-rc0-58-g9275a0f'

PESTATUS = ENV['PESTATUS'] || PESTATUS = 'latest'
PEVERSION = ENV['PEVERSION'] || PEVERSION = '3.1.0'
pe_tarball=''

ptbuser = ENV['ptbuser'] || ptbuser = 'shrug'
$settings = Hash.new
hostos=''

desc "Build and populate data directory"
task :init do
  [BUILDDIR, KSISODIR, CACHEDIR].each do |dir|
    unless File.directory?(dir)
      cputs "Making #{dir} for all kickstart data"
      FileUtils.mkdir_p(dir)
    end
  end
  system("gpg --keyserver pgp.mit.edu --recv-key 4BD6EC30")
  abort("Could not import public key: #{$?}") if $? != 0

  pe_tarball=get_pe(PESTATUS,PEVERSION)

  cputs "Cloning puppet..."
  gitclone 'git://github.com/puppetlabs/puppet.git', "#{CACHEDIR}/puppet.git", 'master'

  cputs "Cloning facter..."
  gitclone 'git://github.com/puppetlabs/facter.git', "#{CACHEDIR}/facter.git", 'master'
  
  cputs "Cloning hiera..."
  gitclone 'git://github.com/puppetlabs/hiera.git', "#{CACHEDIR}/hiera.git", 'master'

  ptbrepo_destination = "#{CACHEDIR}/puppetlabs-training-bootstrap.git"

  STDOUT.sync = true
  STDOUT.flush

  # Set PTB repo
  if File.exist?("#{ptbrepo_destination}/config")
    ptbrepo_default = File.read("#{ptbrepo_destination}/config").match(/url = (\S+)/)[1]
    ptbrepo = ptbrepo_default
    cputs "Current repo url: #{ptbrepo} (`rm` local repo to reset)"
  else
    ptbrepo_default = "git://github.com/#{ptbuser}/puppetlabs-training-bootstrap.git"
    ptbrepo = ENV['ptbrepo_default'] || ptbrepo = ptbrepo_default
  end

  # Set PTB branch
  if File.exist?("#{ptbrepo_destination}/HEAD")
    ptbbranch_default = File.read("#{ptbrepo_destination}/HEAD").match(/.*refs\/heads\/(\S+)/)[1]
  else
    ptbbranch_default = 'feature/re-301'
  end
  ptbbranch = ENV['ptbbranch_default'] || ptbbranch = ptbbranch_default
  cputs "Cloning ptb..."
  gitclone ptbrepo, ptbrepo_destination, ptbbranch
  FileUtils.cp("#{BASEDIR}/tools/.s3cfg", "#{CACHEDIR}/")
end

desc "Destroy VirtualBox instance"
task :destroyvm, [:vmos] do |t,args|
  args.with_defaults(:vmos => $settings[:vmos])
  prompt_vmos(args.vmos)
  if %x{VBoxManage list vms}.match /("#{$settings[:vmname]}")/
    cputs "Destroying VM #{$settings[:vmname]}..."
    system("VBoxManage unregistervm '#{$settings[:vmname]}' --delete")
  end
end

desc "Create a new vmware instance for kickstarting"
task :createvm, [:vmos,:vmtype,:mem] do |t,args|
  args.with_defaults(:vmos => $settings[:vmos],:vmtype => $settings[:vmtype],:mem => (ENV['mem']||'1024'))
  begin
    prompt_vmos(args.vmos)

    Rake::Task[:destroyvm].invoke($settings[:vmos])
    dir = "#{BUILDDIR}/vagrant"
    unless File.directory?(dir)
      FileUtils.mkdir_p(dir)
    end

    case $settings[:vmos]
    when /(Centos|Redhat)/
      ostype = 'RedHat'
    end
    cputs "Creating VM '#{$settings[:vmname]}' in #{dir} ..."
    system("VBoxManage createvm --name '#{$settings[:vmname]}' --basefolder '#{dir}' --register --ostype #{ostype}")
    Dir.chdir("#{dir}/#{$settings[:vmname]}")
    cputs "Configuring VM settings..."
    system("VBoxManage modifyvm '#{$settings[:vmname]}' --memory #{args.mem} --nic1 nat --usb off --audio none --pae on")
    system("VBoxManage storagectl '#{$settings[:vmname]}' --name 'IDE Controller' --add ide")
    system("VBoxManage createhd --filename 'box-disk1.vmdk' --size 8192 --format VMDK")
    system("VBoxManage storageattach '#{$settings[:vmname]}' --storagectl 'IDE Controller' --port 0 --device 0 --type hdd --medium 'box-disk1.vmdk'")
    system("VBoxManage storageattach '#{$settings[:vmname]}' --storagectl 'IDE Controller' --port 1 --device 0 --type dvddrive --medium emptydrive")
  ensure
    Dir.chdir(BASEDIR)
  end
end

desc "Creates a modified ISO with preseed/kickstart"
task :createiso, [:vmos,:vmtype] do |t,args|
  args.with_defaults(:vmos => $settings[:vmos], :vmtype => $settings[:vmtype])
  prompt_vmos(args.vmos)
  prompt_vmtype(args.vmtype)
  case $settings[:vmos]
  when 'Debian'
    # Parse templates and output in BUILDDIR
    $settings[:pe_install_suffix] = '-debian-6-i386'
    if $settings[:vmtype] == 'training'
      $settings[:hostname] = "#{$settings[:vmtype]}.puppetlabs.vm"
    else
      $settings[:hostname] = "learn.localdomain"
    end
    $settings[:pe_tarball] = pe_tarball
    # No variables
    build_file('isolinux.cfg')
    #template_path = "#{BASEDIR}/#{$settings[:vmos]}/#{filename}.erb"
    # Uses hostname, pe_install_suffix
    build_file('preseed.cfg')

    # Define ISO file targets
    files = {
      "#{BUILDDIR}/Debian/isolinux.cfg"               => '/isolinux/isolinux.cfg',
      "#{BUILDDIR}/Debian/preseed.cfg"                => '/puppet/preseed.cfg',
      "#{CACHEDIR}/puppet.git"                        => '/puppet/puppet.git',
      "#{CACHEDIR}/facter.git"                        => '/puppet/facter.git',
      "#{CACHEDIR}/hiera.git"                         => '/puppet/hiera.git',
      "#{CACHEDIR}/puppetlabs-training-bootstrap.git" => '/puppet/puppetlabs-training-bootstrap.git',
      "#{CACHEDIR}/#{$settings[:pe_tarball]}"                     => "/puppet/#{$settings[:pe_tarball]}",
    }
    iso_glob = 'debian-*'
    iso_url = 'http://hammurabi.acc.umu.se/debian-cd/6.0.6/i386/iso-cd/debian-6.0.6-i386-CD-1.iso'
  when 'Centos'
    # Parse templates and output in BUILDDIR
    $settings[:pe_install_suffix] = '-el-6-i386'
    if $settings[:vmtype] == 'training'
      $settings[:hostname] = "#{$settings[:vmtype]}.puppetlabs.vm"
    else
      $settings[:hostname] = "learn.localdomain"
    end

    $settings[:pe_tarball] = pe_tarball
    # No variables
    build_file('isolinux.cfg')
    # Uses hostname, pe_install_suffix
    build_file('ks.cfg')

    unless File.exist?("#{CACHEDIR}/epel-release.rpm")
      cputs "Downloading EPEL rpm"
      #download "http://mirrors.cat.pdx.edu/epel/5/i386/epel-release-5-4.noarch.rpm", "#{CACHEDIR}/epel-release.rpm"
      download "http://mirrors.cat.pdx.edu/epel/6/i386/epel-release-6-8.noarch.rpm", "#{CACHEDIR}/epel-release.rpm"
    end
    
    unless File.exist?("#{CACHEDIR}/puppetlabs-enterprise-release-extras.rpm")
      cputs "Downloading Puppet Enterprise Extras rpm"
      #download "http://mirrors.cat.pdx.edu/epel/5/i386/epel-release-5-4.noarch.rpm", "#{CACHEDIR}/epel-release.rpm"
    download "http://yum-enterprise.puppetlabs.com/el/6/extras/i386/puppetlabs-enterprise-release-extras-6-2.noarch.rpm", "#{CACHEDIR}/puppetlabs-enterprise-release-extras.rpm"
    end
    unless File.exist?("#{CACHEDIR}/builder.ip")
      cputs "Generating builder.ip"
      File.open("#{CACHEDIR}/builder.ip", 'w') do |file| 
        file.write(Facter.value('ipaddress').chomp)
      end
        
    # Define ISO file targets
    files = {
      "#{BUILDDIR}/Centos/isolinux.cfg"               => '/isolinux/isolinux.cfg',
      "#{BUILDDIR}/Centos/ks.cfg"                     => '/puppet/ks.cfg',
      "#{CACHEDIR}/epel-release.rpm"                  => '/puppet/epel-release.rpm',
      "#{CACHEDIR}/puppetlabs-enterprise-release-extras.rpm"  => '/puppet/puppetlabs-enterprise-release-extras.rpm',
      "#{CACHEDIR}/builder.ip"                        => '/puppet/builder.ip',
      "#{CACHEDIR}/puppet.git"                        => '/puppet/puppet.git',
      "#{CACHEDIR}/facter.git"                        => '/puppet/facter.git',
      "#{CACHEDIR}/hiera.git"                        => '/puppet/hiera.git',
      "#{CACHEDIR}/puppetlabs-training-bootstrap.git" => '/puppet/puppetlabs-training-bootstrap.git',
      "#{CACHEDIR}/#{$settings[:pe_tarball]}"                     => "/puppet/#{$settings[:pe_tarball]}",
    }
    iso_glob = 'CentOS-*'
    iso_url = 'http://mirror.tocici.com/centos/6.3/isos/i386/CentOS-6.3-i386-bin-DVD1.iso'
  end


  iso_file = Dir.glob("#{CACHEDIR}/#{iso_glob}").first

  if ! iso_file
    iso_default = iso_url
  else
    iso_default = iso_file
  end
  if ! File.exist?("#{KSISODIR}/#{$settings[:vmos]}.iso")
    iso_uri = ENV['iso_uri'] || iso_uri = iso_default
    if iso_uri != iso_file
      case iso_uri
      when /^(http|https):\/\//
        iso_file = File.basename(iso_uri)
        cputs "Downloading ISO to #{CACHEDIR}/#{iso_file}..."
        download iso_uri, "#{CACHEDIR}/#{iso_file}"
      else
        cputs "Copying ISO to #{CACHEDIR}..."
        FileUtils.cp iso_uri, CACHEDIR
      end
      iso_file = Dir.glob("#{CACHEDIR}/#{iso_glob}").first
    end
    cputs "Mapping files from #{BUILDDIR} into ISO..."
    map_iso(iso_file, "#{KSISODIR}/#{$settings[:vmos]}.iso", files)
  else
    cputs "Image #{KSISODIR}/#{$settings[:vmos]}.iso is already created; skipping"
  end
  # Extract the OS version from the iso filename as debian and centos are the
  # same basic format and get caught by the match group below
  iso_version = iso_default[/^.*-(\d+\.\d+\.?\d?)-.*\.iso$/,1]
  cputs "iso_version of #{iso_default} is #{iso_version}"
  if $settings[:vmtype] == 'training'
    $settings[:vmname] = "#{$settings[:vmos]}-#{iso_version}-pe-#{PEVERSION}".downcase
  else
    $settings[:vmname] = "learn_puppet_#{$settings[:vmos]}-#{iso_version}-pe-#{PEVERSION}".downcase
  end
end

task :mountiso, [:vmos] => [:createiso] do |t,args|
  args.with_defaults(:vmos => $settings[:vmos])
  prompt_vmos(args.vmos)
  cputs "Mounting #{$settings[:vmos]} on #{$settings[:vmname]}"
  system("VBoxManage storageattach '#{$settings[:vmname]}' --storagectl 'IDE Controller' --port 1 --device 0 --type dvddrive --medium '#{KSISODIR}/#{$settings[:vmos]}.iso'")
  Rake::Task[:unmountiso].reenable
end

task :unmountiso, [:vmos] do |t,args|
  args.with_defaults(:vmos => $settings[:vmos])
  prompt_vmos(args.vmos)

  sleeptotal = 0
  while %x{VBoxManage list runningvms}.match /("#{$settings[:vmname]}")/
    cputs "Waiting for #{$settings[:vmname]} to shut down before unmounting..." if sleeptotal >= 90
    sleep 5
    sleeptotal += 5
  end
  cputs "Unmounting #{$settings[:vmos]} on #{$settings[:vmname]}"
  system("VBoxManage storageattach '#{$settings[:vmname]}' --storagectl 'IDE Controller' --port 1 --device 0 --type dvddrive --medium none")
  Rake::Task[:mountiso].reenable
end

desc "Remove the dynamically created ISO"
task :destroyiso, [:vmos] do |t,args|
  args.with_defaults(:vmos => $settings[:vmos])
  prompt_vmos(args.vmos)

  if File.exists?("#{KSISODIR}/#{$settings[:vmos]}.iso")
    cputs "Removing ISO..."
    File.delete("#{KSISODIR}/#{$settings[:vmos]}.iso")
  else
    cputs "No ISO found"
  end
end

desc "Start the VM"
task :startvm, [:vmos] do |t,args|
  args.with_defaults(:vmos => $settings[:vmos])
  prompt_vmos(args.vmos)

  cputs "Starting #{$settings[:vmname]}"
  system("socat tcp-listen:5151 OPEN:${CACHEDIR}/post.log,creat,append &")
  system("VBoxHeadless --startvm '#{$settings[:vmname]}'")
end

desc "Check the result of the install"
task :checklog do
  File.open("#{CACHEDIR}/post.log") do |log|
    abort(result) if result=log.grep(/Error:/)
  end
end

desc "Reload the VM"
task :reloadvm, [:vmos] => [:createvm, :mountiso, :startvm] do |t,args|
  args.with_defaults(:vmos => $settings[:vmos])
  prompt_vmos(args.vmos)
  Rake::Task[:unmountiso].invoke($settings[:vmos])
end

desc "Do everything!"
task :everything, [:vmos] do |t,args|
  args.with_defaults(:vmos => $settings[:vmos])
  prompt_vmos(args.vmos)

  Rake::Task[:init].invoke
  Rake::Task[:createiso].invoke($settings[:vmos])
  Rake::Task[:createvm].invoke($settings[:vmos])
  Rake::Task[:mountiso].invoke($settings[:vmos])
  Rake::Task[:startvm].invoke($settings[:vmos])
  Rake::Task[:checklog].invoke
  Rake::Task[:unmountiso].invoke($settings[:vmos])
  Rake::Task[:createovf].invoke($settings[:vmos])
  Rake::Task[:createvmx].invoke($settings[:vmos])
  Rake::Task[:createvbox].invoke($settings[:vmos])
  Rake::Task[:vagrantize].invoke($settings[:vmos])
  Rake::Task[:packagevm].invoke($settings[:vmos])
  Rake::Task[:shipvm].invoke
end

desc "Force-stop the VM"
task :stopvm, [:vmos] do |t,args|
  args.with_defaults(:vmos => $settings[:vmos])
  prompt_vmos(args.vmos)
  if %x{VBoxManage list runningvms}.match /("#{$settings[:vmname]}")/
    cputs "Stopping #{$settings[:vmname]}"
    system("VBoxManage controlvm '#{$settings[:vmname]}' poweroff")
  end
end

task :createovf, [:vmos] do |t,args|
  args.with_defaults(:vmos => $settings[:vmos])
  prompt_vmos(args.vmos)

  Rake::Task[:unmountiso].invoke($settings[:vmos])
  cputs "Converting Original .vbox to OVF..."
  FileUtils.rm_rf("#{OVFDIR}/#{$settings[:vmname]}-ovf") if File.directory?("#{OVFDIR}/#{$settings[:vmname]}-ovf")
  FileUtils.mkdir_p("#{OVFDIR}/#{$settings[:vmname]}-ovf")
  system("VBoxManage export '#{$settings[:vmname]}' -o '#{OVFDIR}/#{$settings[:vmname]}-ovf/#{$settings[:vmname]}.ovf'")
end

task :createvmx, [:vmos] => [:createovf] do |t,args|
  args.with_defaults(:vmos => $settings[:vmos])
  prompt_vmos(args.vmos)
  hostos = `uname -s`
  if hostos =~ /Darwin/
    ovftool_default = '/Applications/VMware OVF Tool/ovftool' #XXX Dynamicize this
  elsif hostos =~ /Linux/
    ovftool_default = '/usr/bin/ovftool'
  else
    abort("Not tested for this platform: #{myos}")
  end
    
  Rake::Task[:unmountiso].invoke($settings[:vmos])
  cputs "Converting OVF to VMX..."
  FileUtils.rm_rf("#{VMWAREDIR}/#{$settings[:vmname]}-vmware") if File.directory?("#{VMWAREDIR}/#{$settings[:vmname]}-vmware")
  FileUtils.mkdir_p("#{VMWAREDIR}/#{$settings[:vmname]}-vmware")
  
  # TODO: I think this path changes between Mac and linux. Verify and fix the logic
  system("'#{ovftool_default}' --lax --compress=9 --targetType=VMX '#{OVFDIR}/#{$settings[:vmname]}-ovf/#{$settings[:vmname]}.ovf' '#{VMWAREDIR}/#{$settings[:vmname]}-vmware'")

  cputs 'Changing virtualhw.version = "9" to "8"'
  vmxpath = "#{VMWAREDIR}/#{$settings[:vmname]}-vmware/#{$settings[:vmname]}/#{$settings[:vmname]}.vmx"
  content = File.read(vmxpath)
  content = content.gsub(/^virtualhw\.version = "9"$/, 'virtualhw.version = "8"')
  File.open(vmxpath, 'w') { |f| f.puts content }
end

task :createvbox, [:vmos] do |t,args|
  args.with_defaults(:vmos => $settings[:vmos])
  prompt_vmos(args.vmos)

  ovftool_default = '/Applications/VMware OVF Tool/ovftool' #XXX Dynamicize this
  cputs "Making copy of VM for VBOX..."
  FileUtils.rm_rf("#{VBOXDIR}/#{$settings[:vmname]}-vbox") if File.directory?("#{VBOXDIR}/#{$settings[:vmname]}-vbox")
  FileUtils.mkdir_p("#{VBOXDIR}/#{$settings[:vmname]}-vbox")
  system("rsync -a '#{VAGRANTDIR}/#{$settings[:vmname]}/' '#{VBOXDIR}/#{$settings[:vmname]}-vbox'")
end

task :vagrantize, [:vmos] do |t,args|
  args.with_defaults(:vmos => $settings[:vmos])
  prompt_vmos(args.vmos)

  cputs "Vagrantizing VM..."
  system("vagrant package --base '#{$settings[:vmname]}' --output '#{VAGRANTDIR}/#{$settings[:vmname]}.box'")
  FileUtils.ln_sf("#{VAGRANTDIR}/#{$settings[:vmname]}.box", "#{VAGRANTDIR}/#{$settings[:vmos].downcase}-latest.box")
end

desc "Zip up the VMs"
task :packagevm, [:vmos] do |t,args|
  if hostos =~ /Darwin/
    md5cmd='md5'
  elsif hostos =~ /Linux/
    md5cmd='md5sum'
  else
    abort("FIXME: what is the md5 command on #{hostos}?")
  end
  args.with_defaults(:vmos => $settings[:vmos])
  prompt_vmos(args.vmos)
  unless File.exists?("#{CACHEDIR}/vms")
    FileUtils.mkdir_p("#{CACHEDIR}/vms")
  end
  system("zip -rj '#{CACHEDIR}/vms/#{$settings[:vmname]}-ovf.zip' '#{OVFDIR}/#{$settings[:vmname]}-ovf'")
  system("zip -rj '#{CACHEDIR}/vms/#{$settings[:vmname]}-vmware.zip' '#{VMWAREDIR}/#{$settings[:vmname]}-vmware'")
  system("zip -rj '#{CACHEDIR}/vms/#{$settings[:vmname]}-vbox.zip' '#{VBOXDIR}/#{$settings[:vmname]}-vbox'")
  system("#{md5cmd} '#{CACHEDIR}/vms/#{$settings[:vmname]}-ovf.zip' > '#{CACHEDIR}/vms/#{$settings[:vmname]}-ovf.zip.md5'")
  system("#{md5cmd} '#{CACHEDIR}/vms/#{$settings[:vmname]}-vmware.zip' > '#{CACHEDIR}/vms/#{$settings[:vmname]}-vmware.zip.md5'")
  system("#{md5cmd} '#{CACHEDIR}/vms/#{$settings[:vmname]}-vbox.zip' > '#{CACHEDIR}/vms/#{$settings[:vmname]}-vbox.zip.md5'")
  # zip & md5 vagrant
end








# vim: set sw=2 sts=2 et tw=80 :
