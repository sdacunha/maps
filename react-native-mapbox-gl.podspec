require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

default_ios_mapbox_version = '~> 5.9.0'
rnmbgl_ios_version = $ReactNativeMapboxGLIOSVersion || ENV["REACT_NATIVE_MAPBOX_MAPBOX_IOS_VERSION"] || default_ios_mapbox_version
if ENV.has_key?("REACT_NATIVE_MAPBOX_MAPBOX_IOS_VERSION")
  puts "REACT_NATIVE_MAPBOX_MAPBOX_IOS_VERSION env is deprecated please use `$ReactNativeMapboxGLIOSVersion = \"#{rnmbgl_ios_version}\"`"
end

TargetsToChangeToDynamic = ['MapboxMobileEvents']

$RNMBGL = Object.new

def $RNMBGL._add_spm_to_target(project, target, url, requirement, product_name)
  pkg_class = Xcodeproj::Project::Object::XCRemoteSwiftPackageReference
  ref_class = Xcodeproj::Project::Object::XCSwiftPackageProductDependency
  pkg = project.root_object.package_references.find { |p| p.class == pkg_class && p.repositoryURL == url }
  if !pkg
    pkg = project.new(pkg_class)
    pkg.repositoryURL = url
    pkg.requirement = requirement
    project.root_object.package_references << pkg
  end
  ref = target.package_product_dependencies.find { |r| r.class == ref_class && r.package == pkg && r.product_name == product_name }
  if !ref
    ref = project.new(ref_class)
    ref.package = pkg
    ref.product_name = product_name
    target.package_product_dependencies << ref
  end
end

def $RNMBGL.post_install(installer)
    spm_spec = {
      url: "https://github.com/maplibre/maplibre-gl-native-distribution",
      requirement: {
        kind: "exactVersion",
        version: "5.13.0-pre.1"
      },
      product_name: "Mapbox"
    }

    metal_spm_spec = {
      url: "https://github.com/maplibre/maplibre-gl-native-distribution",
      requirement: {
        kind: "exactVersion",
        version: "5.13.0-pre.1"
      },
      product_name: "MetalANGLE"
    }


    project = installer.pods_project
    self._add_spm_to_target(
      project,
      project.targets.find { |t| t.name == "react-native-mapbox-gl"},
      spm_spec[:url],
      spm_spec[:requirement],
      spm_spec[:product_name]
    )

    self._add_spm_to_target(
      project,
      project.targets.find { |t| t.name == "react-native-mapbox-gl"},
      metal_spm_spec[:url],
      metal_spm_spec[:requirement],
      metal_spm_spec[:product_name]
    )

    installer.aggregate_targets.group_by(&:user_project).each do |project, targets|
      targets.each do |target|
        target.user_targets.each do |user_target|
          self._add_spm_to_target(
            project,
            user_target,
            spm_spec[:url],
            spm_spec[:requirement],
            spm_spec[:product_name]
          )
          self._add_spm_to_target(
            project,
            user_target,
            metal_spm_spec[:url],
            metal_spm_spec[:requirement],
            metal_spm_spec[:product_name]
          )
        end
      end
    end
end

def $RNMBGL.pre_install(installer)
  installer.aggregate_targets.each do |target|
    target.pod_targets.select { |p| TargetsToChangeToDynamic.include?(p.name) }.each do |mobile_events_target|
      mobile_events_target.instance_variable_set(:@build_type,Pod::BuildType.dynamic_framework)
      puts "* Changed #{mobile_events_target.name} to #{mobile_events_target.send(:build_type)}"
      fail "Unable to change build_type" unless mobile_events_target.send(:build_type) == Pod::BuildType.dynamic_framework
    end
  end
end

Pod::Spec.new do |s|
  s.name		= "react-native-mapbox-gl"
  s.summary		= "React Native Component for Mapbox GL"
  s.version		= package['version']
  s.authors		= { "Nick Italiano" => "ni6@njit.edu" }
  s.homepage    	= "https://github.com/@sdacunha/maps#readme"
  s.source      	= { :git => "https://github.com/@sdacunha/maps.git" }
  s.license     	= "MIT"
  s.platform    	= :ios, "8.0"

  s.dependency 'React-Core'
  s.dependency 'React'

  s.subspec 'DynamicLibrary' do |sp|
    sp.source_files	= "ios/RCTMGL/**/*.{h,m}"
    # sp.compiler_flags = '-DRNMGL_USE_MAPLIBRE=1'
  end

  if ENV["REACT_NATIVE_MAPBOX_GL_USE_FRAMEWORKS"]
    s.default_subspecs= ['DynamicLibrary']
  else
    s.subspec 'StaticLibraryFixer' do |sp|
      # s.dependency '@react-native-mapbox-gl-mapbox-static', rnmbgl_ios_version
    end

    s.default_subspecs= ['DynamicLibrary', 'StaticLibraryFixer']
  end
end
