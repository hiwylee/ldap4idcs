import React, { useState, useEffect } from 'react';
import { useRouter } from 'next/router';
import Head from 'next/head';
import { motion, AnimatePresence } from 'framer-motion';
import toast from 'react-hot-toast';
import {
  Bars3Icon,
  XMarkIcon,
  UserCircleIcon,
  ArrowRightOnRectangleIcon,
  Cog6ToothIcon,
  HomeIcon,
  RectangleStackIcon,
  ShieldCheckIcon,
  ClockIcon,
  UsersIcon,
  ComputerDesktopIcon,
  ExclamationTriangleIcon
} from '@heroicons/react/24/outline';

import { useAuth } from '../hooks/useAuth';
import { useApplications } from '../hooks/useApplications';
import { LoadingSpinner } from '../components/ui/LoadingSpinner';
import { Button } from '../components/ui/Button';
import { Card } from '../components/ui/Card';
import { SSO IFrame } from '../components/sso/SSOIframe';
import { UserProfile } from '../components/user/UserProfile';
import { ApplicationGrid } from '../components/applications/ApplicationGrid';
import { NavigationSidebar } from '../components/layout/NavigationSidebar';
import { TopNavigation } from '../components/layout/TopNavigation';

interface DashboardTab {
  id: string;
  name: string;
  icon: React.ComponentType<{ className?: string }>;
  component: React.ComponentType;
}

const DashboardPage: React.FC = () => {
  const router = useRouter();
  const { user, logout, isLoading } = useAuth();
  const { applications, isLoading: appsLoading, error: appsError } = useApplications();
  
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [activeTab, setActiveTab] = useState('dashboard');
  const [selectedApp, setSelectedApp] = useState<string | null>(null);

  // Redirect if not authenticated
  useEffect(() => {
    if (!isLoading && !user) {
      router.push('/login');
    }
  }, [user, isLoading, router]);

  // Handle logout
  const handleLogout = async () => {
    try {
      await logout();
      toast.success('로그아웃되었습니다.');
      router.push('/login');
    } catch (error) {
      toast.error('로그아웃 중 오류가 발생했습니다.');
    }
  };

  // Handle app selection
  const handleAppSelect = (appId: string) => {
    setSelectedApp(appId);
    setActiveTab('application');
  };

  const tabs: DashboardTab[] = [
    {
      id: 'dashboard',
      name: '대시보드',
      icon: HomeIcon,
      component: () => (
        <DashboardOverview
          user={user}
          applications={applications}
          onAppSelect={handleAppSelect}
        />
      )
    },
    {
      id: 'applications',
      name: '애플리케이션',
      icon: RectangleStackIcon,
      component: () => (
        <ApplicationGrid
          applications={applications}
          isLoading={appsLoading}
          error={appsError}
          onAppSelect={handleAppSelect}
        />
      )
    },
    {
      id: 'application',
      name: selectedApp ? applications?.find(app => app.id === selectedApp)?.name || '애플리케이션' : '애플리케이션',
      icon: ComputerDesktopIcon,
      component: () => selectedApp ? (
        <SSOIframe appId={selectedApp} />
      ) : (
        <div className="flex items-center justify-center h-64">
          <p className="text-gray-500">애플리케이션을 선택해주세요.</p>
        </div>
      )
    },
    {
      id: 'profile',
      name: '프로필',
      icon: UserCircleIcon,
      component: () => <UserProfile user={user} />
    }
  ];

  const navigation = [
    { name: '대시보드', href: '#', id: 'dashboard', icon: HomeIcon, current: activeTab === 'dashboard' },
    { name: '애플리케이션', href: '#', id: 'applications', icon: RectangleStackIcon, current: activeTab === 'applications' },
    { name: '프로필', href: '#', id: 'profile', icon: UserCircleIcon, current: activeTab === 'profile' },
  ];

  if (isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  if (!user) {
    return null;
  }

  const activeTabComponent = tabs.find(tab => tab.id === activeTab)?.component;

  return (
    <>
      <Head>
        <title>대시보드 - OCI IDCS SSO 플랫폼</title>
        <meta name="description" content="OCI IDCS SSO 플랫폼 대시보드" />
      </Head>

      <div className="min-h-screen bg-gray-50">
        {/* Mobile sidebar */}
        <NavigationSidebar
          navigation={navigation}
          sidebarOpen={sidebarOpen}
          setSidebarOpen={setSidebarOpen}
          onNavigate={setActiveTab}
          user={user}
          onLogout={handleLogout}
        />

        {/* Desktop sidebar */}
        <div className="hidden lg:fixed lg:inset-y-0 lg:z-50 lg:flex lg:w-72 lg:flex-col">
          <div className="flex grow flex-col gap-y-5 overflow-y-auto bg-white px-6 pb-4 shadow-xl">
            {/* Logo */}
            <div className="flex h-16 shrink-0 items-center">
              <div className="flex items-center space-x-3">
                <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-gradient-to-r from-blue-600 to-indigo-600">
                  <ShieldCheckIcon className="h-6 w-6 text-white" />
                </div>
                <div>
                  <h1 className="text-lg font-semibold text-gray-900">SSO Platform</h1>
                  <p className="text-xs text-gray-500">OCI IDCS 통합</p>
                </div>
              </div>
            </div>

            {/* Navigation */}
            <nav className="flex flex-1 flex-col">
              <ul role="list" className="flex flex-1 flex-col gap-y-7">
                <li>
                  <ul role="list" className="-mx-2 space-y-1">
                    {navigation.map((item) => (
                      <li key={item.name}>
                        <button
                          onClick={() => setActiveTab(item.id)}
                          className={`group flex w-full gap-x-3 rounded-md p-2 text-sm leading-6 font-semibold transition-colors ${
                            item.current
                              ? 'bg-blue-50 text-blue-600'
                              : 'text-gray-700 hover:text-blue-600 hover:bg-gray-50'
                          }`}
                        >
                          <item.icon
                            className={`h-6 w-6 shrink-0 ${
                              item.current ? 'text-blue-600' : 'text-gray-400 group-hover:text-blue-600'
                            }`}
                          />
                          {item.name}
                        </button>
                      </li>
                    ))}
                  </ul>
                </li>

                {/* User section */}
                <li className="mt-auto">
                  <div className="flex items-center gap-x-4 px-2 py-3 text-sm font-semibold leading-6 text-gray-900">
                    <div className="h-8 w-8 rounded-full bg-blue-600 flex items-center justify-center">
                      <span className="text-sm font-medium text-white">
                        {user.first_name?.[0] || user.email[0].toUpperCase()}
                      </span>
                    </div>
                    <div className="flex-1 truncate">
                      <p className="truncate text-sm font-medium text-gray-900">
                        {user.first_name} {user.last_name}
                      </p>
                      <p className="truncate text-xs text-gray-500">{user.email}</p>
                    </div>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={handleLogout}
                      className="text-gray-400 hover:text-gray-600"
                    >
                      <ArrowRightOnRectangleIcon className="h-5 w-5" />
                    </Button>
                  </div>
                </li>
              </ul>
            </nav>
          </div>
        </div>

        {/* Main content */}
        <div className="lg:pl-72">
          {/* Top navigation for mobile */}
          <TopNavigation
            user={user}
            onMenuClick={() => setSidebarOpen(true)}
            onLogout={handleLogout}
          />

          {/* Page content */}
          <main className="py-6">
            <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
              <AnimatePresence mode="wait">
                <motion.div
                  key={activeTab}
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: -20 }}
                  transition={{ duration: 0.2 }}
                >
                  {activeTabComponent && React.createElement(activeTabComponent)}
                </motion.div>
              </AnimatePresence>
            </div>
          </main>
        </div>
      </div>
    </>
  );
};

// Dashboard Overview Component
const DashboardOverview: React.FC<{
  user: any;
  applications: any[];
  onAppSelect: (appId: string) => void;
}> = ({ user, applications, onAppSelect }) => {
  const stats = [
    {
      name: '연결된 애플리케이션',
      value: applications?.length || 0,
      icon: RectangleStackIcon,
      color: 'blue'
    },
    {
      name: '활성 세션',
      value: '1',
      icon: ClockIcon,
      color: 'green'
    },
    {
      name: '소속 그룹',
      value: user?.groups?.length || 0,
      icon: UsersIcon,
      color: 'purple'
    },
    {
      name: '보안 등급',
      value: 'High',
      icon: ShieldCheckIcon,
      color: 'emerald'
    }
  ];

  const recentApps = applications?.slice(0, 4) || [];

  return (
    <div className="space-y-6">
      {/* Welcome Section */}
      <div className="bg-gradient-to-r from-blue-600 to-indigo-600 rounded-lg shadow-lg p-6 text-white">
        <h1 className="text-2xl font-bold mb-2">
          안녕하세요, {user.first_name || user.email}님!
        </h1>
        <p className="text-blue-100">
          OCI IDCS SSO 플랫폼에 오신 것을 환영합니다. 
          {user.source === 'idcs' ? ' IDCS' : user.source === 'saml' ? ' SAML' : ' LDAP'} 
          을 통해 안전하게 인증되었습니다.
        </p>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4">
        {stats.map((stat) => (
          <Card key={stat.name} className="p-6">
            <div className="flex items-center">
              <div className="flex-shrink-0">
                <div className={`w-8 h-8 bg-${stat.color}-100 rounded-md flex items-center justify-center`}>
                  <stat.icon className={`w-5 h-5 text-${stat.color}-600`} />
                </div>
              </div>
              <div className="ml-5 w-0 flex-1">
                <dl>
                  <dt className="text-sm font-medium text-gray-500 truncate">
                    {stat.name}
                  </dt>
                  <dd className="text-lg font-semibold text-gray-900">
                    {stat.value}
                  </dd>
                </dl>
              </div>
            </div>
          </Card>
        ))}
      </div>

      {/* Recent Applications */}
      <Card className="p-6">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold text-gray-900">
            최근 사용한 애플리케이션
          </h2>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => onAppSelect('applications')}
          >
            모든 앱 보기
          </Button>
        </div>

        {recentApps.length > 0 ? (
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {recentApps.map((app) => (
              <div
                key={app.id}
                onClick={() => onAppSelect(app.id)}
                className="flex items-center p-4 bg-gray-50 rounded-lg hover:bg-gray-100 cursor-pointer transition-colors"
              >
                <div className="flex-shrink-0">
                  {app.icon ? (
                    <img
                      src={app.icon}
                      alt={app.name}
                      className="w-10 h-10 rounded-lg"
                    />
                  ) : (
                    <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center">
                      <ComputerDesktopIcon className="w-6 h-6 text-blue-600" />
                    </div>
                  )}
                </div>
                <div className="ml-4 flex-1 min-w-0">
                  <p className="text-sm font-medium text-gray-900 truncate">
                    {app.name}
                  </p>
                  <p className="text-xs text-gray-500 truncate">
                    {app.description}
                  </p>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="text-center py-8">
            <ExclamationTriangleIcon className="mx-auto h-12 w-12 text-gray-400" />
            <h3 className="mt-2 text-sm font-medium text-gray-900">
              사용 가능한 애플리케이션이 없습니다
            </h3>
            <p className="mt-1 text-sm text-gray-500">
              관리자에게 애플리케이션 접근 권한을 요청하세요.
            </p>
          </div>
        )}
      </Card>

      {/* Security Info */}
      <Card className="p-6">
        <h2 className="text-lg font-semibold text-gray-900 mb-4">
          보안 정보
        </h2>
        <div className="space-y-3">
          <div className="flex justify-between text-sm">
            <span className="text-gray-500">인증 방법</span>
            <span className="font-medium text-gray-900">
              {user.source === 'idcs' ? 'OCI IDCS' : 
               user.source === 'saml' ? 'SAML 2.0' : 
               user.source === 'ldap' ? 'LDAP' : '알 수 없음'}
            </span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-gray-500">마지막 로그인</span>
            <span className="font-medium text-gray-900">
              {new Date().toLocaleDateString('ko-KR')}
            </span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-gray-500">세션 만료</span>
            <span className="font-medium text-gray-900">
              {new Date(Date.now() + 8 * 60 * 60 * 1000).toLocaleTimeString('ko-KR')}
            </span>
          </div>
        </div>
      </Card>
    </div>
  );
};

export default DashboardPage;