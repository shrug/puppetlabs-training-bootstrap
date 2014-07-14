require 'erb'
require 'uri'
require 'net/http'
require 'net/https'
require 'rubygems'
require 'gpgme'
require 'nokogiri'

STDOUT.sync = true
BASEDIR = File.dirname(__FILE__)
SITESDIR = ENV['sitesdir'] || ENV['HOME'] + "/Sites"
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
PEVERSION = ENV['PEVERSION'] || '3.2.3'
PESTATUS = ENV['PESTATUS'] || 'release'
$settings = Hash.new

hostos = `uname -s`
if hostos =~ /Darwin/
  @ovftool_default = '/Applications/VMware OVF Tool/ovftool'
  @md5 = '/sbin/md5'
elsif hostos =~ /Linux/
  @ovftool_default = '/usr/bin/ovftool'
  @md5 = '/usr/bin/md5sum'
else
  abort("Not tested for this platform: #{hostos}")
end

# Bail politely when handed a 'vmos' that's not supported.
if ENV['vmos'] && ENV['vmos'] !~ /^(Centos|Ubuntu)$/
  abort("ERROR: Unrecognized vmos parameter: #{ENV['vmos']}")
end

# Bail if handed a 'vmtype' that's not supported.
if ENV['vmtype'] && ENV['vmtype'] !~ /^(training|learning)$/
  abort("ERROR: Unrecognized vmtype parameter: #{ENV['vmtype']}")
end

desc "Build and populate data directory"
task :init do
  [BUILDDIR, KSISODIR, CACHEDIR].each do |dir|
    unless File.directory?(dir)
      cputs "Making #{dir} for all kickstart data"
      FileUtils.mkdir_p(dir)
    end
  end

  ['Ubuntu','Centos'].each do |vmos|
    case vmos
    when 'Ubuntu'
      pe_install_suffix = '-ubuntu-12.04-i386'
      @ubuntu_pe_tarball, @ubuntu_agent_tarball = get_pe(pe_install_suffix)
    when 'Centos'
      pe_install_suffix = '-el-6-i386'
      @centos_pe_tarball, @centos_agent_tarball = get_pe(pe_install_suffix)
    end
    cputs "Getting PE tarballs for #{vmos}"
  end

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
  @ptbrepo = nil || ENV['ptbrepo']
  if File.exist?("#{ptbrepo_destination}/config")
    ptbrepo_default = File.read("#{ptbrepo_destination}/config").match(/url = (\S+)/)[1]
    @ptbrepo = ptbrepo_default
    cputs "Current repo url: #{@ptbrepo} (`rm` local repo to reset)"
  else
    # Set PTB user
    cprint "Please choose a github user for puppetlabs-training-bootstrap [puppetlabs]: "
    ptbuser = STDIN.gets.chomp
    ptbuser = 'puppetlabs' if ptbuser.empty?
    ptbrepo_default = "git://github.com/#{ptbuser}/puppetlabs-training-bootstrap.git"
    cprint "Please choose a repo url [#{ptbrepo_default}]: "
    @ptbrepo = STDIN.gets.chomp
    @ptbrepo = ptbrepo_default if @ptbrepo.empty?
  end

  # Set PTB branch
  if File.exist?("#{ptbrepo_destination}/HEAD")
    ptbbranch_default = File.read("#{ptbrepo_destination}/HEAD").match(/.*refs\/heads\/(\S+)/)[1]
  else
    ptbbranch_default = 'master'
  end
  ptbbranch_override = nil || ENV['ptbbranch']
  unless ptbbranch_override
    cprint "Please choose a branch to use for puppetlabs-training-bootstrap [#{ptbbranch_default}]: "
    @ptbbranch = STDIN.gets.chomp
    @ptbbranch = ptbbranch_default if @ptbbranch.empty?
  else
    @ptbbranch = ptbbranch_override
  end

  # Calculate the VM version and build numbers used in the kickstart template
  @ptb_build     = `git rev-parse --short #{@ptbbranch}`.strip
  @ptb_version ||= '[Testing Build]'

  cputs "Cloning ptb: #{@ptbrepo}, #{ptbrepo_destination}, #{@ptbbranch}"
  gitclone @ptbrepo, ptbrepo_destination, @ptbbranch
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
    else
      ostype = $settings[:vmos]
    end
    cputs "Creating VM '#{$settings[:vmname]}' in #{dir} ..."
    system("VBoxManage createvm --name '#{$settings[:vmname]}' --basefolder '#{dir}' --register --ostype #{ostype}")
    Dir.chdir("#{dir}/#{$settings[:vmname]}")
    cputs "Configuring VM settings..."
    system("VBoxManage modifyvm '#{$settings[:vmname]}' --memory #{args.mem} --nic1 nat --usb off --audio none")
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
  when 'Ubuntu'
    # Parse templates and output in BUILDDIR
    $settings[:pe_install_suffix] = '-ubuntu-12.04-i386'
    if $settings[:vmtype] == 'training'
      $settings[:hostname] = "#{$settings[:vmtype]}.puppetlabs.vm"
    else
      $settings[:hostname] = "learn.localdomain"
    end
    $settings[:pe_tarball] = @ubuntu_pe_tarball
    # No variables
    build_file('lang')
    build_file('txt.cfg')
    build_file('isolinux.cfg')
    #template_path = "#{BASEDIR}/#{$settings[:vmos]}/#{filename}.erb"
    # Uses hostname, pe_install_suffix
    build_file('preseed.cfg')

    # Define ISO file targets
    files = {
      "#{BUILDDIR}/Ubuntu/lang"                       => '/isolinux/lang',
      "#{BUILDDIR}/Ubuntu/txt.cfg"                    => '/isolinux/txt.cfg',
      "#{BUILDDIR}/Ubuntu/isolinux.cfg"               => '/isolinux/isolinux.cfg',
      "#{BUILDDIR}/Ubuntu/preseed.cfg"                => '/puppet/preseed.cfg',
      "#{CACHEDIR}/puppet.git"                        => '/puppet/puppet.git',
      "#{CACHEDIR}/facter.git"                        => '/puppet/facter.git',
      "#{CACHEDIR}/puppetlabs-training-bootstrap.git" => '/puppet/puppetlabs-training-bootstrap.git',
      "#{CACHEDIR}/#{$settings[:pe_tarball]}"                     => "/puppet/#{$settings[:pe_tarball]}",
    }
    iso_glob = 'ubuntu-12.04.4-server*'
    iso_url = 'http://mirrors.cat.pdx.edu/ubuntu-releases/12.04.4/ubuntu-12.04.4-server-i386.iso'
  when 'Centos'
    # Parse templates and output in BUILDDIR
    $settings[:pe_install_suffix] = '-el-6-i386'
    if $settings[:vmtype] == 'training'
      $settings[:hostname] = "#{$settings[:vmtype]}.puppetlabs.vm"
    else
      $settings[:hostname] = "learn.localdomain"
    end

    $settings[:pe_tarball]    = @centos_pe_tarball
    $settings[:agent_tarball] = @centos_agent_tarball

    # No variables
    build_file('isolinux.cfg')
    # Uses hostname, pe_install_suffix
    build_file('ks.cfg')

    unless File.exist?("#{CACHEDIR}/epel-release.rpm")
      cputs "Downloading EPEL rpm"
      #download "http://mirrors.cat.pdx.edu/epel/5/i386/epel-release-5-4.noarch.rpm", "#{CACHEDIR}/epel-release.rpm"
      download "http://mirrors.cat.pdx.edu/epel/6/i386/epel-release-6-8.noarch.rpm", "#{CACHEDIR}/epel-release.rpm"
    end

    # Define ISO file targets
    files = {
      "#{BUILDDIR}/Centos/isolinux.cfg"               => '/isolinux/isolinux.cfg',
      "#{BUILDDIR}/Centos/ks.cfg"                     => '/puppet/ks.cfg',
      "#{CACHEDIR}/epel-release.rpm"                  => '/puppet/epel-release.rpm',
      "#{CACHEDIR}/puppet.git"                        => '/puppet/puppet.git',
      "#{CACHEDIR}/facter.git"                        => '/puppet/facter.git',
      "#{CACHEDIR}/hiera.git"                         => '/puppet/hiera.git',
      "#{CACHEDIR}/puppetlabs-training-bootstrap.git" => '/puppet/puppetlabs-training-bootstrap.git',
      "#{CACHEDIR}/#{$settings[:pe_tarball]}"         => "/puppet/#{$settings[:pe_tarball]}",
      "#{CACHEDIR}/#{$settings[:agent_tarball]}"      => "/puppet/#{$settings[:agent_tarball]}",
    }
    iso_glob = 'CentOS-6.5-*'
    iso_url = 'http://mirror.tocici.com/centos/6/isos/i386/CentOS-6.5-i386-bin-DVD1.iso'
  end


  iso_file = Dir.glob("#{CACHEDIR}/#{iso_glob}").first || ENV['iso_file']

  if ! iso_file
    iso_default = iso_url
  else
    iso_default = iso_file
  end
  if ! File.exist?("#{CACHEDIR}/#{$settings[:vmos]}.iso")
    unless iso_file
      cprint "Please specify #{$settings[:vmos]} ISO path or url [#{iso_default}]: "
      iso_uri = STDIN.gets.chomp.rstrip
      iso_uri = iso_default if iso_uri.empty?
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
      end
    end
    cputs "Mapping files from #{BUILDDIR} into ISO..."
    map_iso(iso_file, "#{KSISODIR}/#{$settings[:vmos]}.iso", files)
  else
    cputs "Image #{KSISODIR}/#{$settings[:vmos]}.iso is already created; skipping"
  end
  # Extract the OS version from the iso filename as ubuntu and centos are the
  # same basic format and get caught by the match group below
  iso_version = iso_file[/^.*-(\d+\.\d+\.?\d?)-.*\.iso$/,1]
  if $settings[:vmtype] == 'training'
    $settings[:vmname] = "#{$settings[:vmos]}-#{iso_version}-pe-#{@real_pe_ver}".downcase
  else
    $settings[:vmname] = "learn_puppet_#{$settings[:vmos]}-#{iso_version}-pe-#{@real_pe_ver}".downcase
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
  # Set higher for install, reduce it here for packaging
  system("VBoxManage modifyvm '#{$settings[:vmname]}' --memory 1024")
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
  headless = nil || ENV['vboxheadless']
  args.with_defaults(:vmos => $settings[:vmos])
  prompt_vmos(args.vmos)
  cputs "Starting #{$settings[:vmname]}"
  if headless
    system("VBoxHeadless --startvm '#{$settings[:vmname]}'")
  else
    system("VBoxManage startvm '#{$settings[:vmname]}'")
  end
end

desc "Reload the VM"
task :reloadvm, [:vmos] => [:createvm, :mountiso, :startvm] do |t,args|
  args.with_defaults(:vmos => $settings[:vmos])
  prompt_vmos(args.vmos)
  Rake::Task[:unmountiso].invoke($settings[:vmos])
end

desc "Build a release VM"
task :release do
  require 'yaml'

  versions     = YAML.load_file('version.yaml')
  @ptb_version = "#{versions[:major]}.#{versions[:minor]}"
  cputs "Current release version #{@ptb_version}"

  release = env_prompt('Increment the release version? [Y/n]: ', 'RELEASE')
  if [ 'y', 'yes', '' ].include? release.downcase
    versions[:minor] += 1
    @ptb_version = "#{versions[:major]}.#{versions[:minor]}"
    File.write('version.yaml', versions.to_yaml)
    system("git commit version.yaml -m 'Updating for release #{@ptb_version}'")
  end

  cputs "Building release version #{@ptb_version}"
  Rake::Task[:everything].invoke
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
  Rake::Task[:unmountiso].invoke($settings[:vmos])
  Rake::Task[:createovf].invoke($settings[:vmos])
  Rake::Task[:unmountiso].invoke($settings[:vmos])
  Rake::Task[:createvmx].invoke($settings[:vmos])
  Rake::Task[:createvbox].invoke($settings[:vmos])
  Rake::Task[:vagrantize].invoke($settings[:vmos])
  Rake::Task[:packagevm].invoke($settings[:vmos])
end

task :jenkins_everything, [:vmos] do |t,args|
  args.with_defaults(:vmos => $settings[:vmos])
  prompt_vmos(args.vmos)

  Rake::Task[:init].invoke
  Rake::Task[:createiso].invoke($settings[:vmos])
  Rake::Task[:createvm].invoke($settings[:vmos])
  Rake::Task[:mountiso].invoke($settings[:vmos])
  Rake::Task[:startvm].invoke($settings[:vmos])
  Rake::Task[:unmountiso].invoke($settings[:vmos])
  Rake::Task[:createovf].invoke($settings[:vmos])
  Rake::Task[:createvmx].invoke($settings[:vmos])
  Rake::Task[:createvbox].invoke($settings[:vmos])
  Rake::Task[:vagrantize].invoke($settings[:vmos])
  Rake::Task[:packagevm].invoke($settings[:vmos])
  Rake::Task[:shipvm].invoke
  Rake::Task[:publishvm].invoke
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

task :createvmx, [:vmos] do |t,args|
  args.with_defaults(:vmos => $settings[:vmos])
  prompt_vmos(args.vmos)

  cputs "Converting OVF to VMX..."
  FileUtils.rm_rf("#{VMWAREDIR}/#{$settings[:vmname]}-vmware") if File.directory?("#{VMWAREDIR}/#{$settings[:vmname]}-vmware")
  FileUtils.mkdir_p("#{VMWAREDIR}/#{$settings[:vmname]}-vmware")
  system("'#{@ovftool_default}' --lax --targetType=VMX '#{OVFDIR}/#{$settings[:vmname]}-ovf/#{$settings[:vmname]}.ovf' '#{VMWAREDIR}/#{$settings[:vmname]}-vmware'")

  cputs 'Changing virtualhw.version = to "8"'
  # this path is different on OSX
  if hostos =~ /Darwin/
    @vmxpath = "#{VMWAREDIR}/#{$settings[:vmname]}-vmware/#{$settings[:vmname]}.vmwarevm/#{$settings[:vmname]}.vmx"
  else
    @vmxpath = "#{VMWAREDIR}/#{$settings[:vmname]}-vmware/#{$settings[:vmname]}/#{$settings[:vmname]}.vmx"
  end
  content = File.read(@vmxpath)
  content = content.gsub(/^virtualhw\.version = "\d+"$/, 'virtualhw.version = "8"')
  File.open(@vmxpath, 'w') { |f| f.puts content }
end

task :createvbox, [:vmos] do |t,args|
  args.with_defaults(:vmos => $settings[:vmos])
  prompt_vmos(args.vmos)
  cputs "Making copy of VM for VBOX..."
  FileUtils.rm_rf("#{VBOXDIR}/#{$settings[:vmname]}-vbox") if File.directory?("#{VBOXDIR}/#{$settings[:vmname]}-vbox")
  FileUtils.mkdir_p("#{VBOXDIR}/#{$settings[:vmname]}-vbox")
  system("rsync -a '#{VAGRANTDIR}/#{$settings[:vmname]}' '#{VBOXDIR}/#{$settings[:vmname]}-vbox'")
  orig = "#{VBOXDIR}/#{$settings[:vmname]}-vbox/#{$settings[:vmname]}.vbox"
  FileUtils.cp orig, "#{orig}.backup", :preserve => true
  xml_file = File.read(orig)
  doc = Nokogiri::XML(xml_file)
  adapters = doc.xpath("//vm:Adapter", 'vm' =>'http://www.innotek.de/VirtualBox-settings')
  adapters.each do |adapter|
    adapter['MACAddress'] = ''
  end
  File.open(orig, 'w') {|f| f.puts doc.to_xml }
end

task :vagrantize, [:vmos] do |t,args|
  args.with_defaults(:vmos => $settings[:vmos])
  prompt_vmos(args.vmos)
  cputs "Vagrantizing VM..."
  system("vagrant package --base '#{$settings[:vmname]}' --output '#{VAGRANTDIR}/#{$settings[:vmname]}.box'")
  FileUtils.ln_sf("#{VAGRANTDIR}/#{$settings[:vmname]}.box", "#{VAGRANTDIR}/#{$settings[:vmos].downcase}-latest.box")
end

desc "Zip up the VMs (unimplemented)"
task :packagevm, [:vmos] do |t,args|
  args.with_defaults(:vmos => $settings[:vmos])
  prompt_vmos(args.vmos)

  version  = @ptb_version.gsub(/[\w\.]/, '')
  filename = "#{CACHEDIR}/#{$settings[:vmname]}-ptb#{version}"

  system("zip -rj '#{filename}-ovf.zip'    '#{OVFDIR}/#{$settings[:vmname]}-ovf'")
  system("zip -rj '#{filename}-vmware.zip' '#{VMWAREDIR}/#{$settings[:vmname]}-vmware'")
  system("zip -rj '#{filename}-vbox.zip'   '#{VBOXDIR}/#{$settings[:vmname]}-vbox'")

  system("#{@md5} '#{filename}-ovf.zip'    > '#{filename}-ovf.zip.md5'")
  system("#{@md5} '#{filename}-vmware.zip' > '#{filename}-vmware.zip.md5'")
  system("#{@md5} '#{filename}-vbox.zip'   > '#{filename}-vbox.zip.md5'")
  # zip & md5 vagrant
end

desc "Unmount the ISO and remove kickstart files and repos"
task :clean, [:del] do |t,args|
  args.with_defaults(:del => $settings[:del])
  prompt_del(args.del)
  cputs "Destroying vms"
  ['Ubuntu','Centos'].each do |os|
    Rake::Task[:destroyvm].invoke(os)
    Rake::Task[:destroyvm].reenable
  end
  cputs "Removing #{BUILDDIR}"
  FileUtils.rm_rf(BUILDDIR) if File.directory?(BUILDDIR)
  if $settings[:del] == 'yes'
    cputs "Removing packaged VMs"
    FileUtils.rm Dir.glob("#{CACHEDIR}/*-pe-#{@real_pe_ver}*.zip*")
  end
end

## Ship the VMs somewhere. These dirs are NFS exports mounted on the builder, so really only
## applicable to the Jenkins builds.
task :shipvm do
  # These currently map to int-resources.ops.puppetlabs.net
  case $settings[:vmtype]
  when /training/
    destdir = "/mnt/nfs/Training\ VM/"
  when /learning/
    destdir = "/mnt/nfs/Learning\ Puppet\ VM/"
  end
  ## There seems to be an intermittent issue with copying to int-resources. Retry up to 3 times.
  3.times do
    begin
      FileUtils.cp_r Dir.glob("#{CACHEDIR}/#{$settings[:vmname]}*"), destdir, :verbose => true
      break
    rescue
      puts "Couldn't copy file(s), waiting 30 seconds then retrying..."
      sleep 30
    end
  end
end

## Publish to VMware
task :publishvm do
  if $settings[:vmtype] == 'learning'
    # Should probably move most of this to a method
    require 'yaml'
    require 'rbvmomi'
    # Manually place a file with the VMware credentials in #{CACHEDIR}
    vcenter_settings = YAML::load(File.open("#{CACHEDIR}/.vmwarecfg.yml"))
    # Do the thing here
    cputs "Publishing to vSphere"
    sh "/usr/bin/ovftool --noSSLVerify --network='delivery.puppetlabs.net' --datastore='instance1' -o --powerOffTarget -n=learn #{VMWAREDIR}/#{$settings[:vmname]}-vmware/#{$settings[:vmname]}/#{$settings[:vmname]}.vmx vi://#{vcenter_settings["username"]}\@puppetlabs.com:#{vcenter_settings["password"]}@vcenter.ops.puppetlabs.net/pdx_office/host/delivery"
    vim = RbVmomi::VIM.connect host: 'vcenter.ops.puppetlabs.net', user: "#{vcenter_settings["username"]}\@puppetlabs.com", password: "#{vcenter_settings["password"]}", insecure: 'true'
    dc = vim.serviceInstance.find_datacenter('pdx_office') or fail "datacenter not found"
    vm = dc.find_vm("Delivery/Release/learn") or fail "VM not found"
    vm.PowerOnVM_Task.wait_for_completion
    vm_ip = nil
    3.times do
      vm_ip = vm.guest_ip
      break unless vm_ip == nil
      sleep 30
    end
    sshpass_scp_to("files/setup.sh", "root@#{vm_ip}", ".")
    remote_sshpass_cmd("root@#{vm_ip}", "bash -x ./setup.sh")
  else
    cputs "Skipping - only publish the learning VM"
  end
end

task :cloud_install , [:vmos,:vmtype] do |t,args|
  args.with_defaults(:vmos => $settings[:vmos], :vmtype => $settings[:vmtype])
  if $settings[:vmtype] == 'training'
    $settings[:hostname] = "#{$settings[:vmtype]}.puppetlabs.vm"
    $settings[:vmname] = "#{$settings[:vmos]}-6.5-pe-#{@real_pe_ver}".downcase
    
  else
    $settings[:hostname] = "learn.localdomain"
    $settings[:vmname] = "learn_puppet_#{$settings[:vmos]}-6.5-pe-#{@real_pe_ver}".downcase   
  end
  $settings[:pe_tarball]    = @centos_pe_tarball
  $settings[:agent_tarball] = @centos_agent_tarball
  prompt_vmos(args.vmos)
  prompt_vmtype(args.vmtype)
  build_file("install.sh")
  cputs "Cloning source template"
  newvm,vm_ip=clone_vm("Delivery/Release/pe-education-vm-template-centos-6.5", $settings[:vmname])
  sshpass_scp_to("#{CACHEDIR}/#{$settings[:pe_tarball]}", "root@#{vm_ip}", ".")
  sshpass_scp_to("#{CACHEDIR}/#{$settings[:agent_tarball]}", "root@#{vm_ip}", ".")
  sshpass_scp_to("#{BUILDDIR}/#{$settings[:vmos]}/install.sh", "root@#{vm_ip}", ".")
  cputs "Configuring VM and installing PE"
  remote_sshpass_cmd("root@#{vm_ip}", "bash -x ./install.sh")
  puts "Powering off #{$settings[:vmname]}"
  newvm.PowerOffVM_Task.wait_for_completion
  cputs "Retrieving #{$settings[:vmname]} as an OVF"
  retrieve_vm($settings[:vmname])
  newvm.Destroy_Task.wait_for_completion
end

task :jenkins_everything_is_cloudy, [:vmos] do |t,args|
  args.with_defaults(:vmos => $settings[:vmos])
  prompt_vmos(args.vmos)
  Rake::Task[:init].invoke
  Rake::Task[:cloud_install].invoke($settings[:vmos])
  Rake::Task[:createvmx].invoke($settings[:vmos])
  Rake::Task[:createvbox].invoke($settings[:vmos])
  Rake::Task[:vagrantize].invoke($settings[:vmos])
  Rake::Task[:packagevm].invoke($settings[:vmos])
  Rake::Task[:shipvm].invoke
  Rake::Task[:publishvm].invoke
end

def clone_vm(source, dest)
  require 'yaml'
  require 'rbvmomi'
  vcenter_settings = YAML::load(File.open("#{CACHEDIR}/.vmwarecfg.yml"))
  vim = RbVmomi::VIM.connect(host: 'vcenter.ops.puppetlabs.net',
                    user: "#{vcenter_settings["username"]}\@puppetlabs.com",
                    password: "#{vcenter_settings["password"]}", 
                    insecure: 'true')
  dc = vim.serviceInstance.find_datacenter('pdx_office') or abort "datacenter not found"
  vm = dc.find_vm(source) or abort "Source VM not found"
  relocateSpec = RbVmomi::VIM.VirtualMachineRelocateSpec
  spec = RbVmomi::VIM.VirtualMachineCloneSpec(:location => relocateSpec,
                                     :powerOn => true,
                                     :template => false)
  vm.CloneVM_Task(:folder => vm.parent, :name => dest, :spec => spec).wait_for_completion
  newvm = dc.find_vm("Delivery/Release/#{dest}") or abort "Destination VM not found"
  vm_ip = nil
  3.times do
    vm_ip = newvm.guest_ip
    break unless vm_ip == nil
    sleep 30
  end
  return newvm,vm_ip
end

def retrieve_vm(vmname)
  require 'yaml'
  vcenter_settings = YAML::load(File.open("#{CACHEDIR}/.vmwarecfg.yml"))
  FileUtils.rm_rf("#{OVFDIR}/#{$settings[:vmname]}-ovf") if File.directory?("#{OVFDIR}/#{$settings[:vmname]}-ovf")
  FileUtils.mkdir_p("#{OVFDIR}/")
  sh "/usr/bin/ovftool --noSSLVerify --powerOffSource vi://#{vcenter_settings["username"]}\@puppetlabs.com:#{vcenter_settings["password"]}@vcenter.ops.puppetlabs.net/pdx_office/vm/Delivery/Release/#{vmname}  #{OVFDIR}/"
  FileUtils.mv("#{OVFDIR}/#{$settings[:vmname]}", "#{OVFDIR}/#{$settings[:vmname]}-ovf")
  FileUtils.rm_rf("#{VAGRANTDIR}/#{$settings[:vmname]}") if File.directory?("#{VAGRANTDIR}/#{$settings[:vmname]}")
  FileUtils.mkdir_p("#{VAGRANTDIR}/#{$settings[:vmname]}")
  FileUtils.cp("#{OVFDIR}/#{$settings[:vmname]}-ovf/#{$settings[:vmname]}-disk1.vmdk", "#{VAGRANTDIR}/#{$settings[:vmname]}")
  begin
    dir = "#{BUILDDIR}/vagrant"
    cputs "Creating VM '#{$settings[:vmname]}' in #{dir} ..."
    system("VBoxManage createvm --name '#{$settings[:vmname]}' --basefolder '#{dir}' --register --ostype RedHat")
    Dir.chdir("#{dir}/#{$settings[:vmname]}")
    cputs "Configuring VM settings..."
    system("VBoxManage modifyvm '#{$settings[:vmname]}' --memory #{args.mem} --nic1 nat --usb off --audio none")
    system("VBoxManage storagectl '#{$settings[:vmname]}' --name 'IDE Controller' --add ide")
    system("VBoxManage storageattach '#{$settings[:vmname]}' --storagectl 'IDE Controller' --port 0 --device 0 --type hdd --medium #{$settings[:vmname]}-disk1.vmdk")
  ensure
    Dir.chdir(BASEDIR)
  end
end

def create_ovf(vmname)
  cputs "Converting Original VM to OVF..."
  FileUtils.rm_rf("#{OVFDIR}/#{$settings[:vmname]}-ovf") if File.directory?("#{OVFDIR}/#{$settings[:vmname]}-ovf")
  FileUtils.mkdir_p("#{OVFDIR}/#{$settings[:vmname]}-ovf")
  sh "/usr/bin/ovftool -tt OVF --noSSLVerify vi://#{vcenter_settings["username"]}\@puppetlabs.com:#{vcenter_settings["password"]}@vcenter.ops.puppetlabs.net/pdx_office/host/delivery/#{$settings[:vmname]} #{OVFDIR}/#{$settings[:vmname]}-ovf/#{$settings[:vmname]}.ovf"
end

def create_vmx(vmname)
  cputs "Converting Original VM to VMX..."
    FileUtils.rm_rf("#{VMWAREDIR}/#{$settings[:vmname]}-vmware") if File.directory?("#{VMWAREDIR}/#{$settings[:vmname]}-vmware")
    FileUtils.mkdir_p("#{VMWAREDIR}/#{$settings[:vmname]}-vmware")
    system("'#{@ovftool_default}' --lax --targetType=VMX '#{OVFDIR}/#{$settings[:vmname]}-ovf/#{$settings[:vmname]}.ovf' '#{VMWAREDIR}/#{$settings[:vmname]}-vmware'")

    cputs 'Changing virtualhw.version = to "8"'
    # this path is different on OSX
    if hostos =~ /Darwin/
      @vmxpath = "#{VMWAREDIR}/#{$settings[:vmname]}-vmware/#{$settings[:vmname]}.vmwarevm/#{$settings[:vmname]}.vmx"
    else
      @vmxpath = "#{VMWAREDIR}/#{$settings[:vmname]}-vmware/#{$settings[:vmname]}/#{$settings[:vmname]}.vmx"
    end
    content = File.read(@vmxpath)
    content = content.gsub(/^virtualhw\.version = "\d+"$/, 'virtualhw.version = "8"')
    File.open(@vmxpath, 'w') { |f| f.puts content }
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

def gitclone(source,destination,branch)
  if File.directory?(destination) then
    system("cd #{destination} && (git fetch origin '+refs/heads/*:refs/heads/*' && git update-server-info && git symbolic-ref HEAD refs/heads/#{branch})") or raise(Error, "Cannot pull ${source}")
  else
    system("git clone --bare #{source} #{destination} && cd #{destination} && git update-server-info && git symbolic-ref HEAD refs/heads/#{branch}") or raise(Error, "Cannot clone #{source}")
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

def prompt_del(del=nil)
  del = del || ENV['del']
  loop do
    cprint "Do you want to delete the packaged VMs in #{CACHEDIR}? [no]: "
    del = STDIN.gets.chomp.downcase
    del = 'no' if del.empty?
    puts del
    if del !~ /(y|n|yes|no)/
      cputs "Please answer with yes or no (y/n)."
    else
      break #loop
    end
  end unless del
  if del =~ /(y|yes)/
    $settings[:del] = 'yes'
  else
    $settings[:del] = 'no'
  end
end

def prompt_vmos(osname=nil)
  osname = osname || ENV['vmos']
  loop do
    cprint "Please choose an OS type of 'Centos' or 'Ubuntu' [Centos]: "
    osname = STDIN.gets.chomp
    osname = 'Centos' if osname.empty?
    if osname !~ /(Ubuntu|Centos)/
      cputs "Incorrect/unknown OS: #{osname}"
    else
      break #loop
    end
  end unless osname
  $settings[:vmos] = osname
end

def prompt_vmtype(type=nil)
  type = type || ENV['vmtype']
  loop do
    cprint "Please choose the type of VM - one of 'training' or 'learning' [training]: "
    type = STDIN.gets.chomp
    type = 'training' if type.empty?
    if type !~ /(training|learning)/
      cputs "Incorrect/unknown type of VM: #{type}"
    else
      break #loop
    end
  end unless type
  $settings[:vmtype] = type
end

def build_file(filename)
  template_path = "#{BASEDIR}/files/#{$settings[:vmos]}/#{filename}.erb"
  target_dir = "#{BUILDDIR}/#{$settings[:vmos]}"
  target_path = "#{target_dir}/#{filename}"
  FileUtils.mkdir(target_dir) unless File.directory?(target_dir)
  if File.file?(template_path)
    cputs "Building #{target_path}..."
    File.open(target_path,'w') do |f|
      template_content = ERB.new(File.read(template_path)).result
      f.write(template_content)
    end
  else
    cputs "No source template found: #{template_path}"
  end
end

def map_iso(indev,outdev,paths)
  maps = paths.collect do |frompath,topath|
    "-map '#{frompath}' '#{topath}'"
  end.join(' ')
  system("xorriso -osirrox on -boot_image any patch -indev #{indev} -outdev #{outdev} #{maps}")
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

# If we want a test version, figure out the latest in the series and download it, otherwise get the release version
def get_pe(pe_install_suffix)
  if PESTATUS =~ /latest/
    perelease=PEVERSION.split('.')
    @real_pe_ver=`curl http://neptune.delivery.puppetlabs.net/#{perelease[0]}.#{perelease[1]}/ci-ready/LATEST`.chomp
  else
    @real_pe_ver=PEVERSION
  end
  cputs "Actual PE version is #{@real_pe_ver}"
  perelease = @real_pe_ver.split('.')
  if PESTATUS =~ /latest/
    url_prefix    = "http://neptune.delivery.puppetlabs.net/#{perelease[0]}.#{perelease[1]}/ci-ready"
    pe_tarball    = "puppet-enterprise-#{@real_pe_ver}#{pe_install_suffix}.tar"
    agent_tarball = "puppet-enterprise-#{@real_pe_ver}#{pe_install_suffix}-agent.tar.gz"
  elsif PESTATUS =~ /release/
    url_prefix    = "https://s3.amazonaws.com/pe-builds/released/#{@real_pe_ver}"
    pe_tarball    = "puppet-enterprise-#{@real_pe_ver}#{pe_install_suffix}.tar.gz"
    agent_tarball = "puppet-enterprise-#{@real_pe_ver}#{pe_install_suffix}-agent.tar.gz"
  else
    abort("Status: #{PESTATUS} not valid - use 'release' or 'latest'.")
  end
  installer       = "#{CACHEDIR}/#{pe_tarball}"
  agent_installer = "#{CACHEDIR}/#{agent_tarball}"
  unless File.exist?(installer)
    cputs "Downloading PE tarball #{@real_pe_ver}..."
    download("#{url_prefix}/#{pe_tarball}", installer)
  end
  unless File.exist?(agent_installer)
    cputs "Downloading PE agent tarball #{@real_pe_ver}..."
    download("#{url_prefix}/#{agent_tarball}", agent_installer)
  end
  if PESTATUS =~ /release/
    unless File.exist?("#{installer}.asc")
      cputs "Downloading PE signature asc file for #{@real_pe_ver}..."
      download "#{url_prefix}/#{pe_tarball}.asc", "#{CACHEDIR}/#{pe_tarball}.asc"
    end
    unless File.exist?("#{agent_installer}.asc")
      cputs "Downloading PE agent signature asc file for #{@real_pe_ver}..."
      download "#{url_prefix}/#{agent_tarball}.asc", "#{CACHEDIR}/#{agent_tarball}.asc"
    end

    cputs "Verifying installer signature"
    raise ('Installer verification failed') unless system("gpg --verify --always-trust #{installer}.asc #{installer}")
    cputs "Verifying agent signature"
    raise ('Agent verification failed') unless  system("gpg --verify --always-trust #{agent_installer}.asc #{agent_installer}")
  end
  return [ pe_tarball, agent_tarball ]
end

def sshpass_scp_to(file, host, remote_path)
  puts "Sending #{file} to #{host}:#{remote_path}"
  ex(%Q[SSHPASS="puppet" sshpass -e scp -r #{file} #{host}:#{remote_path}])
end

def sshpass_scp_from(file, host, remote_path)
  puts "Retrieving #{file} from #{host}:#{remote_path}"
  ex(%Q[SSHPASS="puppet" sshpass -e scp -r #{host}:#{remote_path} #{file}])
end

def remote_sshpass_cmd(host, command, verbose = true)
  check_tool('sshpass')
  if verbose
    puts "Executing '#{command}' on #{host}"
    %x{SSHPASS="puppet" sshpass -e ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t #{host} '#{command.gsub("'", "'\\\\''")}'}
  else
    %x{SSHPASS="puppet" sshpass -e ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -t #{host} '#{command.gsub("'", "'\\\\''")}' > /dev/null 2>&1}
    if $?.success?
      return true
    else
      raise RuntimeError
    end
  end
end

def check_tool(tool)
  return true if has_tool(tool)
  fail "#{tool} tool not found...exiting"
end

def find_tool(tool)
  ENV['PATH'].split(File::PATH_SEPARATOR).each do |root|
     location = File.join(root, tool)
     return location if FileTest.executable? location
  end
  return nil
end
alias :has_tool :find_tool

# ex combines the behavior of `%x{cmd}` and rake's `sh "cmd"`. `%x{cmd}` has
# the benefit of returning the standard out of an executed command, enabling us
# to query the file system, e.g. `contents = %x{ls}`. The drawback to `%x{cmd}`
# is that on failure of a command (something returned non-zero) the return of
# `%x{cmd}` is just an empty string. As such, we can't know if we succeeded.
# Rake's `sh "cmd"`, on the other hand, will raise a RuntimeError if a command
# does not return 0, but doesn't return any of the stdout from the command -
# only true or false depending on its success or failure. With `ex(cmd)` we
# purport to both return the results of the command execution (ala `%x{cmd}`)
# while also raising an exception if a command does not succeed (ala `sh "cmd"`).
def ex(command)
  ret = %x[#{command}]
  unless $?.success?
    raise RuntimeError
  end
  ret
end

# vim: set sw=2 sts=2 et tw=80 :
