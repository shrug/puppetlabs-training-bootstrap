desc "Unmount the ISO and remove kickstart files and repos"
task :clean, [:del] do |t,args|
  args.with_defaults(:del => $settings[:del])
  $settings[:del] = 'yes'
  #prompt_del(args.del)

  cputs "Destroying vms"
  ['Debian','Centos'].each do |os|
    Rake::Task[:destroyvm].invoke(os)
    Rake::Task[:destroyvm].reenable
  end
  cputs "CACHEDIR is #{CACHEDIR}"
  cputs "Removing #{BUILDDIR}"
  FileUtils.rm_rf(BUILDDIR) if File.directory?(BUILDDIR)
  cputs "Removing cloned repos"
  FileUtils.rm_rf(Dir.glob(CACHEDIR+"/*.git"))
  cputs "Removing tarballs"
  FileUtils.rm_rf(Dir.glob(CACHEDIR+"/*.tar*"))
  if $settings[:del] == 'yes'
    cputs "Removing packaged VMs"
    FileUtils.rm_rf(Dir.glob(CACHEDIR+"/vms/*.zip*"))
  end
  if File.exist?(CACHEDIR+"/post.log")
    cputs "Archiving post.log"
    FileUtils.mv CACHEDIR+"/post.log", CACHEDIR+"/post.log_lastrun", :force => true
  end
end