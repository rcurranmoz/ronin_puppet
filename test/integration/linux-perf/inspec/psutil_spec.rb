require_relative 'spec_helper'

# no more py2
#
# describe command('pip list | grep psutil') do
#   its(:exit_status) { should eq 0 }
#   its(:stdout) { should match /psutil/ }
# end

describe command('pip3 list | grep psutil') do
  its(:exit_status) { should eq 0 }
  its(:stdout) { should match /psutil/ }
end
