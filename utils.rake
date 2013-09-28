require 'net/http'

def get_pe(status, version)
  
  perelease = pever.split('.')
  if status =~ /latest/ || status =~ /test/
    url_prefix = "http://neptune.delivery.puppetlabs.net/#{perelease[0]}.#{perelease[1]}/ci-ready"
    pe_tarball = "puppet-enterprise-#{@real_pe_ver}-el-6-i386.tar"
  elsif status =~ /release/
    url_prefix = "https://s3.amazonaws.com/pe-builds/released"
    pe_tarball = "puppet-enterprise-#{@real_pe_ver}-el-6-i386.tar.gz"
  else 
    abort("Status: #{status} not valid - use 'test', 'release' or 'latest'.")
  end
  installer = "#{CACHEDIR}/#{pe_tarball}"
  unless File.exist?(installer)
    cputs "Downloading PE tarball #{@real_pe_ver}..."
    download("#{url_prefix}/#{pe_tarball}", installer)
  end
  if status =~ /release/
    unless File.exist?("#{installer}.asc")
      cputs "Downloading PE signature asc file for #{@real_pe_ver}..."
      download "#{url_prefix}/#{pe_tarball}.asc", "#{CACHEDIR}/#{pe_tarball}.asc"
    end
  end
  return pe_tarball
  
end

def get_latest_pe_version(version)
  perelease=version.split('.')
  latest=`curl http://neptune.delivery.puppetlabs.net/#{perelease[0]}.#{perelease[1]}/ci-ready/LATEST`.chomp
  return latest
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
  osname = ENV['vmos'] || osname= 'Centos'
  $settings[:vmos] = osname
end

def prompt_vmtype(type=nil)
  type = ENV['vmtype'] || type = 'learning'
    if type !~ /(training|learning)/
      abort("Incorrect/unknown type of VM: #{type}")
    end
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


# vim: set sw=2 sts=2 et tw=80 :