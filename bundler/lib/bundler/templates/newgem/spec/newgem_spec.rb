describe <%= conifg[:constant_name] %> do
  it 'should have a version number' do
    <%= config[:constant_name] %>::VERSION.should_not be_nil
  end

  it 'should do something useful' do
    false.should be_true
  end
end
