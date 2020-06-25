# @summary Set up a local 389DS server
#
# @param package_list
#   A list of packages that will installed instead of the internally selected
#   packages.
#
# @author https://github.com/simp/pupmod-simp-ds389/graphs/contributors
#
class ds389::install (
  Optional[Array[String]] $package_list = undef
) {
  assert_private()

  if $package_list {
    $_389_packages = $package_list
  }
  else {
    if $ds389::enable_admin_service {
      $_389_packages = '389-admin'
      $_setup_command = '/sbin/setup-ds-admin.pl'

      ensure_packages(['389-ds-console', '389-admin-console'], { ensure => $ds389::package_ensure })
    }
    else {
      $_389_packages = '389-ds-base'
      $_setup_command = '/sbin/setup-ds.pl'
    }
  }

  ensure_packages($_389_packages, { ensure => $ds389::package_ensure })
}
