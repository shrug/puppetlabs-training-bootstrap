desc "Ship the VMs somewhere"
task :shipvm => [:packagevm] do
  system("s3cmd --config=#{CACHEDIR}/.s3cfg sync #{CACHEDIR}/vms s3://pe-lvm")
  
end